using System.Security.Claims;
using Biblioteca.Api.Data;
using Biblioteca.Api.Infrastructure;
using Biblioteca.Api.Security;
using Dapper;

namespace Biblioteca.Api.Features;

public record ReferenceInput(string? Nome, string? Nacionalidade = null, string? Email = null, string? Descricao = null);
public record BookInput(string? Titulo, int IdEditora, int IdCategoria, int AnoPublicacao,
    int NumeroEdicao, int[]? IdsAutores, string? Isbn = null);
public record CopyInput(int IdLivro, string? CodigoTombo, DateTime DataAquisicao);
public record CopyStateInput(string? Situacao);

public static class Catalog
{
    private record Resource(string Table, string Id, string Columns);
    private static readonly Dictionary<string, Resource> Resources = new()
    {
        ["editoras"] = new("EDITORAS", "IdEditora", "IdEditora,Nome,Nacionalidade,Email"),
        ["categorias"] = new("CATEGORIAS", "IdCategoria", "IdCategoria,Nome,Descricao"),
        ["autores"] = new("AUTORES", "IdAutor", "IdAutor,Nome,Nacionalidade")
    };

    public static void MapCatalog(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1").RequireAuthorization().WithTags("Catálogo");
        foreach (var (route, resource) in Resources)
        {
            // Identificadores SQL vêm somente deste mapa constante, nunca da entrada do cliente.
            group.MapGet("/" + route, async (Db db, string? q, int? page, int? pageSize, CancellationToken ct) =>
            {
                var pg = Guard.Paging(page, pageSize);
                var search = Guard.Optional(q, "Busca", 160);
                await using var cn = await db.Open(ct);
                var args = new { Q = search, pg.Offset, pg.Size };
                var items = await cn.QueryAsync($"SELECT {resource.Columns} FROM dbo.{resource.Table} WHERE @Q IS NULL OR CHARINDEX(@Q,Nome)>0 ORDER BY Nome,{resource.Id} OFFSET @Offset ROWS FETCH NEXT @Size ROWS ONLY", args);
                var total = await cn.ExecuteScalarAsync<int>($"SELECT COUNT(*) FROM dbo.{resource.Table} WHERE @Q IS NULL OR CHARINDEX(@Q,Nome)>0", args);
                return Results.Ok(new { items, total, page = pg.Page, pageSize = pg.Size });
            }).WithName("Listar_" + route);
            group.MapPost("/" + route, (ReferenceInput input, Db db, ClaimsPrincipal user, CancellationToken ct)
                => SaveReference(null, route, resource, input, db, user.UserId(), ct))
                .RequireAuthorization("Staff").WithName("Criar_" + route);
            group.MapPut("/" + route + "/{id:int}", (int id, ReferenceInput input, Db db, ClaimsPrincipal user, CancellationToken ct)
                => SaveReference(id, route, resource, input, db, user.UserId(), ct))
                .RequireAuthorization("Staff").WithName("Atualizar_" + route);
        }
        group.MapGet("/livros", async (Db db, string? q, int? idCategoria, int? page, int? pageSize, CancellationToken ct) =>
        {
            var pg = Guard.Paging(page, pageSize);
            var search = Guard.Optional(q, "Busca", 250);
            await using var cn = await db.Open(ct);
            var args = new { Q = search, IdCategoria = idCategoria, pg.Offset, pg.Size };
            const string filter = "(@Q IS NULL OR CHARINDEX(@Q,l.Titulo)>0 OR CHARINDEX(@Q,l.Isbn)>0) AND (@IdCategoria IS NULL OR l.IdCategoria=@IdCategoria)";
            var items = await cn.QueryAsync($"""
                SELECT l.*, e.Nome AS Editora, c.Nome AS Categoria,
                    (SELECT COUNT(*) FROM dbo.EXEMPLARES x WHERE x.IdLivro=l.IdLivro AND x.Situacao='DISPONIVEL') AS Disponiveis
                FROM dbo.LIVROS l JOIN dbo.EDITORAS e ON e.IdEditora=l.IdEditora
                JOIN dbo.CATEGORIAS c ON c.IdCategoria=l.IdCategoria WHERE {filter}
                ORDER BY l.Titulo,l.IdLivro OFFSET @Offset ROWS FETCH NEXT @Size ROWS ONLY
                """, args);
            var total = await cn.ExecuteScalarAsync<int>($"SELECT COUNT(*) FROM dbo.LIVROS l WHERE {filter}", args);
            return Results.Ok(new { items, total, page = pg.Page, pageSize = pg.Size });
        }).WithName("ListarLivros");
        group.MapGet("/livros/{id:int}", async Task<IResult> (int id, Db db, CancellationToken ct) =>
        {
            await using var cn = await db.Open(ct);
            var book = await cn.QuerySingleOrDefaultAsync("""
                SELECT l.*,e.Nome AS Editora,c.Nome AS Categoria FROM dbo.LIVROS l
                JOIN dbo.EDITORAS e ON e.IdEditora=l.IdEditora JOIN dbo.CATEGORIAS c ON c.IdCategoria=l.IdCategoria
                WHERE l.IdLivro=@id
                """, new { id });
            if (book is null) throw new ApiException(404, "Livro não encontrado.");
            ((IDictionary<string, object>)book)["Autores"] = await cn.QueryAsync("SELECT a.* FROM dbo.AUTORES a JOIN dbo.LIVROS_AUTORES la ON la.IdAutor=a.IdAutor WHERE la.IdLivro=@id ORDER BY a.Nome", new { id });
            ((IDictionary<string, object>)book)["Exemplares"] = await cn.QueryAsync("SELECT * FROM dbo.EXEMPLARES WHERE IdLivro=@id ORDER BY CodigoTombo", new { id });
            return Results.Ok(book);
        }).WithName("DetalharLivro");
        group.MapPost("/livros", (BookInput input, Db db, ClaimsPrincipal user, CancellationToken ct)
            => SaveBook(null, input, db, user.UserId(), ct)).RequireAuthorization("Staff").WithName("CriarLivro");
        group.MapPut("/livros/{id:int}", (int id, BookInput input, Db db, ClaimsPrincipal user, CancellationToken ct)
            => SaveBook(id, input, db, user.UserId(), ct)).RequireAuthorization("Staff").WithName("AtualizarLivro");

        group.MapGet("/exemplares", async (Db db, int? idLivro, string? situacao, int? page, int? pageSize, CancellationToken ct) =>
        {
            var pg = Guard.Paging(page, pageSize);
            var state = Guard.Optional(situacao, "Situação", 20);
            await using var cn = await db.Open(ct);
            var args = new { IdLivro = idLivro, Situacao = state, pg.Offset, pg.Size };
            const string filter = "(@IdLivro IS NULL OR x.IdLivro=@IdLivro) AND (@Situacao IS NULL OR x.Situacao=@Situacao)";
            var items = await cn.QueryAsync($"SELECT x.*,l.Titulo,l.Isbn FROM dbo.EXEMPLARES x JOIN dbo.LIVROS l ON l.IdLivro=x.IdLivro WHERE {filter} ORDER BY x.IdExemplar OFFSET @Offset ROWS FETCH NEXT @Size ROWS ONLY", args);
            var total = await cn.ExecuteScalarAsync<int>($"SELECT COUNT(*) FROM dbo.EXEMPLARES x WHERE {filter}", args);
            return Results.Ok(new { items, total, page = pg.Page, pageSize = pg.Size });
        }).WithName("ListarExemplares");
        group.MapGet("/exemplares/codigo/{codigo}", async Task<IResult> (string codigo, Db db, CancellationToken ct) =>
        {
            var code = Guard.Text(codigo, "Código de tombo", 60);
            await using var cn = await db.Open(ct);
            var item = await cn.QuerySingleOrDefaultAsync("SELECT x.*,l.Titulo,l.Isbn FROM dbo.EXEMPLARES x JOIN dbo.LIVROS l ON l.IdLivro=x.IdLivro WHERE x.CodigoTombo=@code", new { code });
            if (item is null) throw new ApiException(404, "Código de exemplar não encontrado.");
            return Results.Ok(item);
        }).WithName("ConsultarCodigoExemplar");
        group.MapPost("/exemplares", async (CopyInput input, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            Guard.That(input.IdLivro > 0 && input.DataAquisicao.Year >= 1900 && input.DataAquisicao.Date <= DateTime.UtcNow.Date, "Informe o livro e uma data de aquisição válida, sem data futura.");
            var code = Guard.Text(input.CodigoTombo, "Código de tombo", 60);
            await using var cn = await db.Open(ct);
            using var tx = cn.BeginTransaction();
            var id = await cn.ExecuteScalarAsync<int>("INSERT dbo.EXEMPLARES(IdLivro,CodigoTombo,Situacao,DataAquisicao) OUTPUT inserted.IdExemplar VALUES(@IdLivro,@code,'DISPONIVEL',@DataAquisicao)", new { input.IdLivro, code, input.DataAquisicao }, tx);
            await Db.Audit(cn, tx, user.UserId(), "EXEMPLAR_CRIADO", $"IdExemplar={id}");
            tx.Commit();
            return Results.Created($"/api/v1/exemplares/codigo/{Uri.EscapeDataString(code)}", new { idExemplar = id });
        }).RequireAuthorization("Staff").WithName("CriarExemplar");
        group.MapPatch("/exemplares/{id:int}/situacao", async (int id, CopyStateInput input, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            Guard.That(input.Situacao is "DISPONIVEL" or "MANUTENCAO" or "INATIVO", "Use DISPONIVEL, MANUTENCAO ou INATIVO. A circulação controla EMPRESTADO.");
            await using var cn = await db.Open(ct);
            using var tx = cn.BeginTransaction();
            var current = await cn.QuerySingleOrDefaultAsync<string>("SELECT Situacao FROM dbo.EXEMPLARES WITH(UPDLOCK,HOLDLOCK) WHERE IdExemplar=@id", new { id }, tx);
            if (current is null) throw new ApiException(404, "Exemplar não encontrado.");
            if (current == "EMPRESTADO") throw new ApiException(409, "Registre a devolução antes de alterar a situação do exemplar.");
            await cn.ExecuteAsync("UPDATE dbo.EXEMPLARES SET Situacao=@Situacao WHERE IdExemplar=@id", new { input.Situacao, id }, tx);
            await Db.Audit(cn, tx, user.UserId(), "EXEMPLAR_ALTERADO", $"IdExemplar={id};Situacao={input.Situacao}");
            tx.Commit();
            return Results.NoContent();
        }).RequireAuthorization("Staff").WithName("AlterarSituacaoExemplar");

        group.MapDelete("/exemplares/{id:int}", async (int id, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await using var cn = await db.Open(ct);
            using var tx = cn.BeginTransaction();
            var copy = await cn.QuerySingleOrDefaultAsync<(string Situacao, string CodigoTombo)>(
                "SELECT Situacao, CodigoTombo FROM dbo.EXEMPLARES WITH(UPDLOCK,HOLDLOCK) WHERE IdExemplar=@id", new { id }, tx);
            if (copy.CodigoTombo is null) throw new ApiException(404, "Exemplar não encontrado.");
            if (copy.Situacao == "EMPRESTADO") throw new ApiException(409, "Exemplar está atualmente emprestado. Registre a devolução antes de excluir.");

            var hasLoans = await cn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM dbo.ITENS_EMPRESTIMO WHERE IdExemplar=@id", new { id }, tx);
            if (hasLoans > 0)
                throw new ApiException(409, "Este exemplar possui histórico de empréstimos e não pode ser apagado para manter a auditoria. Altere sua situação para INATIVO.");

            await cn.ExecuteAsync("DELETE FROM dbo.EXEMPLARES WHERE IdExemplar=@id", new { id }, tx);
            await Db.Audit(cn, tx, user.UserId(), "EXEMPLAR_EXCLUIDO", $"IdExemplar={id};Codigo={copy.CodigoTombo}");
            tx.Commit();
            return Results.NoContent();
        }).RequireAuthorization("Staff").WithName("ExcluirExemplar");

        group.MapDelete("/livros/{id:int}", async (int id, Db db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await using var cn = await db.Open(ct);
            using var tx = cn.BeginTransaction();
            var book = await cn.QuerySingleOrDefaultAsync<string>(
                "SELECT Titulo FROM dbo.LIVROS WITH(UPDLOCK,HOLDLOCK) WHERE IdLivro=@id", new { id }, tx);
            if (book is null) throw new ApiException(404, "Livro não encontrado.");

            var activeLoans = await cn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(*) FROM dbo.ITENS_EMPRESTIMO i 
                JOIN dbo.EXEMPLARES x ON x.IdExemplar = i.IdExemplar 
                WHERE x.IdLivro = @id AND i.DataHoraDevolucao IS NULL", new { id }, tx);
            if (activeLoans > 0)
                throw new ApiException(409, "Não é possível excluir livro com exemplares atualmente emprestados.");

            var anyLoans = await cn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(*) FROM dbo.ITENS_EMPRESTIMO i 
                JOIN dbo.EXEMPLARES x ON x.IdExemplar = i.IdExemplar 
                WHERE x.IdLivro = @id", new { id }, tx);
            if (anyLoans > 0)
                throw new ApiException(409, "Livro possui exemplares com histórico de empréstimos. Para preservar o histórico, inative seus exemplares.");

            await cn.ExecuteAsync("DELETE FROM dbo.EXEMPLARES WHERE IdLivro=@id", new { id }, tx);
            await cn.ExecuteAsync("DELETE FROM dbo.LIVROS_AUTORES WHERE IdLivro=@id", new { id }, tx);
            await cn.ExecuteAsync("DELETE FROM dbo.LIVROS WHERE IdLivro=@id", new { id }, tx);
            await Db.Audit(cn, tx, user.UserId(), "LIVRO_EXCLUIDO", $"IdLivro={id};Titulo={book}");
            tx.Commit();
            return Results.NoContent();
        }).RequireAuthorization("Staff").WithName("ExcluirLivro");
    }

    private static async Task<IResult> SaveReference(int? id, string route, Resource resource, ReferenceInput input, Db db, int actor, CancellationToken ct)
    {
        var name = Guard.Text(input.Nome, "Nome", route == "categorias" ? 100 : 160);
        var nation = Guard.Optional(input.Nacionalidade, "Nacionalidade", 80);
        var email = Guard.Optional(input.Email, "E-mail", 254);
        if (email is not null) Guard.That(new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(email), "E-mail inválido.");
        var description = Guard.Optional(input.Descricao, "Descrição", 500);
        var args = new { Id = id, Nome = name, Nacionalidade = nation, Email = email, Descricao = description };
        var (cols, vals, sets) = route switch
        {
            "editoras" => ("Nome,Nacionalidade,Email", "@Nome,@Nacionalidade,@Email", "Nome=@Nome,Nacionalidade=@Nacionalidade,Email=@Email"),
            "categorias" => ("Nome,Descricao", "@Nome,@Descricao", "Nome=@Nome,Descricao=@Descricao"),
            _ => ("Nome,Nacionalidade", "@Nome,@Nacionalidade", "Nome=@Nome,Nacionalidade=@Nacionalidade")
        };
        await using var cn = await db.Open(ct);
        using var tx = cn.BeginTransaction();
        int saved;
        if (id is null) saved = await cn.ExecuteScalarAsync<int>($"INSERT dbo.{resource.Table}({cols}) OUTPUT inserted.{resource.Id} VALUES({vals})", args, tx);
        else
        {
            saved = id.Value;
            if (await cn.ExecuteAsync($"UPDATE dbo.{resource.Table} SET {sets} WHERE {resource.Id}=@Id", args, tx) == 0)
                throw new ApiException(404, "Cadastro não encontrado.");
        }
        await Db.Audit(cn, tx, actor, resource.Table + (id is null ? "_CRIADO" : "_ALTERADO"), $"Id={saved}");
        tx.Commit();
        var body = new Dictionary<string, object> { [resource.Id] = saved };
        return id is null ? Results.Created($"/api/v1/{route}", body) : Results.Ok(body);
    }

    private static async Task<IResult> SaveBook(int? id, BookInput input, Db db, int actor, CancellationToken ct)
    {
        var title = Guard.Text(input.Titulo, "Título", 250);
        var isbn = Guard.Optional(input.Isbn, "ISBN", 17)?.Replace("-", "");
        if (isbn is not null) Guard.That(System.Text.RegularExpressions.Regex.IsMatch(isbn, @"^([0-9]{13}|[0-9]{9}[0-9Xx])$"), "Informe ISBN-10 ou ISBN-13.");
        Guard.That(input.IdEditora > 0 && input.IdCategoria > 0, "Editora e categoria são obrigatórias.");
        Guard.That(input.AnoPublicacao >= 1450 && input.AnoPublicacao <= DateTime.UtcNow.Year + 1 && input.NumeroEdicao is >= 1 and <= 999, "Ano ou edição inválidos.");
        Guard.That(input.IdsAutores is { Length: > 0 and <= 50 } && input.IdsAutores.All(x => x > 0) && input.IdsAutores.Distinct().Count() == input.IdsAutores.Length, "Informe entre 1 e 50 autores sem repetição.");
        await using var cn = await db.Open(ct);
        using var tx = cn.BeginTransaction();
        var args = new { Id = id, Titulo = title, Isbn = isbn, input.IdEditora, input.IdCategoria, input.AnoPublicacao, input.NumeroEdicao };
        int saved;
        if (id is null)
            saved = await cn.ExecuteScalarAsync<int>("INSERT dbo.LIVROS(Titulo,Isbn,IdEditora,IdCategoria,AnoPublicacao,NumeroEdicao) OUTPUT inserted.IdLivro VALUES(@Titulo,@Isbn,@IdEditora,@IdCategoria,@AnoPublicacao,@NumeroEdicao)", args, tx);
        else
        {
            saved = id.Value;
            if (await cn.ExecuteAsync("UPDATE dbo.LIVROS SET Titulo=@Titulo,Isbn=@Isbn,IdEditora=@IdEditora,IdCategoria=@IdCategoria,AnoPublicacao=@AnoPublicacao,NumeroEdicao=@NumeroEdicao WHERE IdLivro=@Id", args, tx) == 0)
                throw new ApiException(404, "Livro não encontrado.");
            await cn.ExecuteAsync("DELETE dbo.LIVROS_AUTORES WHERE IdLivro=@saved", new { saved }, tx);
        }
        await cn.ExecuteAsync("INSERT dbo.LIVROS_AUTORES(IdLivro,IdAutor) VALUES(@IdLivro,@IdAutor)", input.IdsAutores!.Select(author => new { IdLivro = saved, IdAutor = author }), tx);
        await Db.Audit(cn, tx, actor, id is null ? "LIVRO_CRIADO" : "LIVRO_ALTERADO", $"IdLivro={saved}");
        tx.Commit();
        return id is null ? Results.Created($"/api/v1/livros/{saved}", new { idLivro = saved }) : Results.Ok(new { idLivro = saved });
    }
}
