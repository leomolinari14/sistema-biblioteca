using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Biblioteca.Api.Data;
using Biblioteca.Api.Infrastructure;
using Biblioteca.Api.Security;
using Dapper;

namespace Biblioteca.Api.Features;

public record SelfCheckoutInput(string[]? CodigosExemplares);
public record SelfReturnInput(string[]? CodigosExemplares);
public record LoanInput(int IdUsuario, string[]? CodigosExemplares);
public record ReturnInput(int[]? IdsExemplares);
public record RulesInput(int LimiteExemplares, int PrazoDias, bool BloquearAtrasados, bool SelfCheckoutHabilitado);

public static class Circulation
{
    public static void MapCirculation(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1").RequireAuthorization().WithTags("Circulação e self-checkout");
        group.MapPost("/self-checkout/emprestimos", async (SelfCheckoutInput input, Db db, ClaimsPrincipal user, CancellationToken ct)
            => await CreateLoan(user.UserId(), user.UserId(), "SELF_CHECKOUT", input.CodigosExemplares, db, user, ct))
            .RequireAuthorization("Reader").WithName("ConfirmarSelfCheckout")
            .WithSummary("Leitor confirma a retirada dos exemplares em sua própria conta.");
        group.MapPost("/self-checkout/devolucoes", async (SelfReturnInput input, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            Guard.That(input.CodigosExemplares is { Length: > 0 and <= 100 },
                "Informe de 1 a 100 códigos de exemplares para devolver.");
            var normalized = input.CodigosExemplares!
                .Select(code => Guard.Text(code, "Código de exemplar", 60))
                .ToArray();
            Guard.That(normalized.Distinct(StringComparer.OrdinalIgnoreCase).Count() == normalized.Length,
                "O mesmo exemplar não pode ser incluído duas vezes.");

            await using var cn = await db.Open(ct);
            var items = (await cn.QueryAsync(new CommandDefinition("dbo.SP_REGISTRAR_AUTODEVOLUCAO", new
            {
                IdUsuario = user.UserId(),
                CodigosJson = JsonSerializer.Serialize(normalized)
            }, commandType: CommandType.StoredProcedure, cancellationToken: ct))).ToArray();
            return Results.Ok(new { quantidade = items.Length, itens = items });
        }).RequireAuthorization("Reader").WithName("ConfirmarAutoDevolucao")
            .WithSummary("Leitor devolve exemplares atualmente emprestados em sua própria conta.");
        group.MapPost("/emprestimos", async (LoanInput input, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            Guard.That(input.IdUsuario > 0, "Informe o usuário que receberá os exemplares.");
            return await CreateLoan(input.IdUsuario, user.UserId(), "BALCAO", input.CodigosExemplares, db, user, ct);
        }).RequireAuthorization("Staff").WithName("CriarEmprestimoBalcao");

        group.MapGet("/me/emprestimos", (Db db, ClaimsPrincipal user, string? situacao, int? page, int? pageSize, CancellationToken ct)
            => ListLoans(db, user.UserId(), situacao, page, pageSize, ct)).WithName("MeusEmprestimos");
        group.MapGet("/emprestimos", (Db db, int? idUsuario, string? situacao, int? page, int? pageSize, CancellationToken ct)
            => ListLoans(db, idUsuario, situacao, page, pageSize, ct)).RequireAuthorization("Staff").WithName("ListarEmprestimos");
        group.MapGet("/emprestimos/{id:long}", async (long id, Db db, ClaimsPrincipal user, CancellationToken ct)
            => Results.Ok(await Receipt(id, db, user, ct))).WithName("ComprovanteEmprestimo");
        group.MapPost("/emprestimos/{id:long}/devolucoes", async (long id, ReturnInput input, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            Guard.That(input.IdsExemplares is { Length: > 0 and <= 100 }
                && input.IdsExemplares.All(x => x > 0)
                && input.IdsExemplares.Distinct().Count() == input.IdsExemplares.Length,
                "Informe de 1 a 100 exemplares diferentes para devolver.");
            await using (var cn = await db.Open(ct))
                await cn.QuerySingleAsync<long>(new CommandDefinition("dbo.SP_REGISTRAR_DEVOLUCAO", new
                {
                    IdEmprestimo = id, IdOperador = user.UserId(),
                    IdsExemplaresJson = JsonSerializer.Serialize(input.IdsExemplares)
                }, commandType: CommandType.StoredProcedure, cancellationToken: ct));
            return Results.Ok(await Receipt(id, db, user, ct));
        }).RequireAuthorization("Staff").WithName("RegistrarDevolucao");

        group.MapGet("/configuracoes", async (Db db, CancellationToken ct) =>
        {
            await using var cn = await db.Open(ct);
            return Results.Ok(await cn.QuerySingleAsync("SELECT LimiteExemplares,PrazoDias,BloquearAtrasados,SelfCheckoutHabilitado FROM dbo.CONFIGURACOES WHERE Id=1"));
        }).WithName("ConsultarRegras");
        group.MapPut("/configuracoes", async (RulesInput input, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            Guard.That(input.LimiteExemplares is >= 1 and <= 100 && input.PrazoDias is >= 1 and <= 365,
                "Limite deve estar entre 1 e 100 exemplares; prazo entre 1 e 365 dias.");
            await using var cn = await db.Open(ct);
            using var tx = cn.BeginTransaction();
            await cn.ExecuteAsync("""
                UPDATE dbo.CONFIGURACOES SET LimiteExemplares=@LimiteExemplares,PrazoDias=@PrazoDias,
                    BloquearAtrasados=@BloquearAtrasados,SelfCheckoutHabilitado=@SelfCheckoutHabilitado WHERE Id=1
                """, input, tx);
            await Db.Audit(cn, tx, user.UserId(), "CONFIGURACOES_ALTERADAS", JsonSerializer.Serialize(input));
            tx.Commit();
            return Results.Ok(input);
        }).RequireAuthorization("Admin").WithName("AlterarRegras");
        group.MapGet("/auditoria", async (Db db, int? page, int? pageSize, CancellationToken ct) =>
        {
            var pg = Guard.Paging(page, pageSize);
            await using var cn = await db.Open(ct);
            var items = await cn.QueryAsync("SELECT IdLogSistema,IdUsuario,Evento,Detalhes,DataHoraEvento FROM dbo.TBL_LOG_SISTEMA ORDER BY DataHoraEvento DESC,IdLogSistema OFFSET @Offset ROWS FETCH NEXT @Size ROWS ONLY", new { pg.Offset, pg.Size });
            var total = await cn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.TBL_LOG_SISTEMA");
            return Results.Ok(new { items, total, page = pg.Page, pageSize = pg.Size });
        }).RequireAuthorization("Admin").WithName("ConsultarAuditoria");
    }

    private static async Task<IResult> CreateLoan(int borrower, int actor, string channel, string[]? codes, Db db, ClaimsPrincipal user, CancellationToken ct)
    {
        Guard.That(codes is { Length: > 0 and <= 100 }, "Informe de 1 a 100 códigos de exemplares.");
        var normalized = codes!.Select(c => Guard.Text(c, "Código de exemplar", 60)).ToArray();
        Guard.That(normalized.Distinct(StringComparer.OrdinalIgnoreCase).Count() == normalized.Length, "O mesmo exemplar não pode ser incluído duas vezes.");
        long id;
        await using (var cn = await db.Open(ct))
            id = await cn.QuerySingleAsync<long>(new CommandDefinition("dbo.SP_CRIAR_EMPRESTIMO", new
            {
                IdUsuario = borrower, IdOperador = actor, Canal = channel,
                CodigosJson = JsonSerializer.Serialize(normalized)
            }, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        return Results.Created($"/api/v1/emprestimos/{id}", await Receipt(id, db, user, ct));
    }

    private static async Task<object> Receipt(long id, Db db, ClaimsPrincipal user, CancellationToken ct)
    {
        await using var cn = await db.Open(ct);
        var staff = user.IsInRole("ADMINISTRADOR") || user.IsInRole("BIBLIOTECARIO");
        var loan = await cn.QuerySingleOrDefaultAsync("""
            SELECT e.*,u.Nome AS NomeUsuario FROM dbo.EMPRESTIMOS e JOIN dbo.USUARIOS u ON u.IdUsuario=e.IdUsuario
            WHERE e.IdEmprestimo=@id AND (@staff=1 OR e.IdUsuario=@actor)
            """, new { id, staff, actor = user.UserId() });
        if (loan is null) throw new ApiException(404, "Empréstimo não encontrado.");
        var items = await cn.QueryAsync("""
            SELECT i.IdItemEmprestimo,i.IdExemplar,x.CodigoTombo,l.Titulo,i.DataHoraDevolucao
            FROM dbo.ITENS_EMPRESTIMO i JOIN dbo.EXEMPLARES x ON x.IdExemplar=i.IdExemplar
            JOIN dbo.LIVROS l ON l.IdLivro=x.IdLivro WHERE i.IdEmprestimo=@id ORDER BY i.IdItemEmprestimo
            """, new { id });
        ((IDictionary<string, object>)loan)["Itens"] = items;
        return loan;
    }

    private static async Task<IResult> ListLoans(Db db, int? idUsuario, string? situacao, int? page, int? pageSize, CancellationToken ct)
    {
        var pg = Guard.Paging(page, pageSize);
        Guard.That(situacao is null or "ABERTO" or "FINALIZADO", "Use situação ABERTO ou FINALIZADO.");
        await using var cn = await db.Open(ct);
        const string filter = "(@IdUsuario IS NULL OR e.IdUsuario=@IdUsuario) AND (@Situacao IS NULL OR e.Situacao=@Situacao)";
        var args = new { IdUsuario = idUsuario, Situacao = situacao, pg.Offset, pg.Size };
        var items = await cn.QueryAsync($"""
            SELECT e.*,u.Nome AS NomeUsuario,
                (SELECT COUNT(*) FROM dbo.ITENS_EMPRESTIMO i WHERE i.IdEmprestimo=e.IdEmprestimo) AS QuantidadeItens,
                (SELECT COUNT(*) FROM dbo.ITENS_EMPRESTIMO i WHERE i.IdEmprestimo=e.IdEmprestimo AND i.DataHoraDevolucao IS NULL) AS ItensPendentes,
                CAST(CASE WHEN e.DataHoraPrevista<SYSUTCDATETIME() AND e.Situacao='ABERTO' THEN 1 ELSE 0 END AS bit) AS Atrasado
            FROM dbo.EMPRESTIMOS e JOIN dbo.USUARIOS u ON u.IdUsuario=e.IdUsuario WHERE {filter}
            ORDER BY e.IdEmprestimo DESC OFFSET @Offset ROWS FETCH NEXT @Size ROWS ONLY
            """, args);
        var total = await cn.ExecuteScalarAsync<int>($"SELECT COUNT(*) FROM dbo.EMPRESTIMOS e WHERE {filter}", args);
        return Results.Ok(new { items, total, page = pg.Page, pageSize = pg.Size });
    }
}
