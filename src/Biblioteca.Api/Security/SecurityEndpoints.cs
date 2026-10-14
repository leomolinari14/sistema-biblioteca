using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Biblioteca.Api.Data;
using Biblioteca.Api.Infrastructure;
using Dapper;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;

namespace Biblioteca.Api.Security;

public static class SecurityEndpoints
{
    private const string PublicColumns = "IdUsuario, Nome, Cpf, Email, Username, Perfil, Ativo, DataCadastro";

    public static IEndpointRouteBuilder MapLibrarySecurity(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("/api/v1/auth").WithTags("Autenticação");
        auth.MapPost("/login", Login).AllowAnonymous().RequireRateLimiting("login")
            .WithSummary("Autentica o usuário e emite um token válido por 60 minutos.");
        auth.MapPost("/cadastro-aluno", RegisterStudent).AllowAnonymous().RequireRateLimiting("login")
            .WithSummary("Permite que um aluno crie uma conta ativa com perfil LEITOR.");
        auth.MapGet("/me", Me).RequireAuthorization()
            .WithSummary("Consulta o perfil do usuário autenticado.");

        var users = app.MapGroup("/api/v1/usuarios").WithTags("Usuários").RequireAuthorization("Staff");
        users.MapPost("/", CreateUser).WithSummary("Cadastra um usuário; bibliotecários cadastram somente leitores.");
        users.MapGet("/", ListUsers).WithSummary("Lista usuários com paginação.");
        users.MapGet("/{id:int}", GetUser).WithSummary("Consulta um usuário pelo identificador.");
        users.MapPatch("/{id:int}/ativo", SetActive).RequireAuthorization("Admin")
            .WithSummary("Ativa ou desativa um usuário, preservando ao menos um administrador ativo.");
        users.MapDelete("/{id:int}", DeleteStudent).RequireAuthorization("Admin")
            .WithSummary("Exclui um aluno que ainda não possui histórico de empréstimos.");
        return app;
    }

    private static async Task<IResult> Login(
        LoginRequest request, Db db, TokenService tokens,
        IPasswordHasher<UserRecord> hasher, CancellationToken ct)
    {
        var username = request.Username?.Trim();
        if (string.IsNullOrEmpty(username) || username.Length > 80 ||
            string.IsNullOrEmpty(request.Senha) || request.Senha.Length > 128)
            throw InvalidCredentials();

        await using var connection = await db.Open(ct);
        var user = await connection.QuerySingleOrDefaultAsync<UserRecord>(new CommandDefinition(
            $"SELECT {PublicColumns}, SenhaHash FROM dbo.USUARIOS WHERE Username = @username;",
            new { username }, cancellationToken: ct));
        var result = tokens.Verify(user, request.Senha);
        if (user is null || !user.Ativo || result == PasswordVerificationResult.Failed)
            throw InvalidCredentials();

        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            var hash = hasher.HashPassword(user, request.Senha);
            await connection.ExecuteAsync(new CommandDefinition(
                "UPDATE dbo.USUARIOS SET SenhaHash = @hash WHERE IdUsuario = @id;",
                new { hash, id = user.IdUsuario }, transaction, cancellationToken: ct));
        }
        await Db.Audit(connection, transaction, user.IdUsuario, "LOGIN", "Autenticação realizada.");
        await transaction.CommitAsync(ct);

        return Results.Ok(new
        {
            accessToken = tokens.Issue(user),
            tokenType = "Bearer",
            expiresIn = JwtSettings.ExpiresInSeconds,
            usuario = new { user.IdUsuario, user.Nome, user.Perfil, user.Username }
        });
    }

    private static async Task<IResult> Me(ClaimsPrincipal principal, Db db, CancellationToken ct)
    {
        await using var connection = await db.Open(ct);
        var user = await connection.QuerySingleOrDefaultAsync<UserRecord>(new CommandDefinition(
            $"SELECT {PublicColumns} FROM dbo.USUARIOS WHERE IdUsuario = @id AND Ativo = 1;",
            new { id = principal.UserId() }, cancellationToken: ct));
        if (user is null)
            throw new ApiException(StatusCodes.Status401Unauthorized, "Usuário indisponível. Entre novamente.");
        return Results.Ok(UserResponse.From(user));
    }

    private static async Task<IResult> RegisterStudent(
        CreateUserRequest request, Db db,
        IPasswordHasher<UserRecord> hasher, CancellationToken ct)
    {
        // O perfil é definido no servidor: não é possível usar o cadastro público
        // para criar bibliotecários ou administradores.
        var studentRequest = request with { Perfil = Profiles.Reader };
        var user = UserValidation.Validate(studentRequest);
        user.SenhaHash = hasher.HashPassword(user, studentRequest.Senha!);

        await using var connection = await db.Open(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        try
        {
            user.IdUsuario = await connection.QuerySingleAsync<int>(new CommandDefinition("""
                INSERT INTO dbo.USUARIOS (Nome, Cpf, Email, Username, SenhaHash, Perfil, Ativo)
                OUTPUT INSERTED.IdUsuario
                VALUES (@Nome, @Cpf, @Email, @Username, @SenhaHash, @Perfil, 1);
                """, user, transaction, cancellationToken: ct));
            await Db.Audit(connection, transaction, user.IdUsuario, "ALUNO_AUTOCADASTRADO",
                JsonSerializer.Serialize(new { user.IdUsuario }));
            await transaction.CommitAsync(ct);
        }
        catch (SqlException exception) when (exception.Number is 2601 or 2627)
        {
            throw new ApiException(StatusCodes.Status409Conflict, "Username, e-mail ou CPF já cadastrado.");
        }

        return Results.Created($"/api/v1/usuarios/{user.IdUsuario}", new
        {
            user.IdUsuario,
            Perfil = Profiles.Reader
        });
    }

    private static async Task<IResult> CreateUser(
        CreateUserRequest request, ClaimsPrincipal principal, Db db,
        IPasswordHasher<UserRecord> hasher, CancellationToken ct)
    {
        var user = UserValidation.Validate(request);
        if (!principal.IsInRole(Profiles.Administrator) && user.Perfil != Profiles.Reader)
            throw new ApiException(StatusCodes.Status403Forbidden, "Bibliotecários podem cadastrar somente leitores.");
        user.SenhaHash = hasher.HashPassword(user, request.Senha!);

        await using var connection = await db.Open(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        try
        {
            user.IdUsuario = await connection.QuerySingleAsync<int>(new CommandDefinition("""
                INSERT INTO dbo.USUARIOS (Nome, Cpf, Email, Username, SenhaHash, Perfil, Ativo)
                OUTPUT INSERTED.IdUsuario
                VALUES (@Nome, @Cpf, @Email, @Username, @SenhaHash, @Perfil, 1);
                """, user, transaction, cancellationToken: ct));
            await Db.Audit(connection, transaction, principal.UserId(), "USUARIO_CRIADO",
                JsonSerializer.Serialize(new { user.IdUsuario, user.Perfil }));
            await transaction.CommitAsync(ct);
        }
        catch (SqlException exception) when (exception.Number is 2601 or 2627)
        {
            throw new ApiException(StatusCodes.Status409Conflict, "Username, e-mail ou CPF já cadastrado.");
        }
        return Results.Created($"/api/v1/usuarios/{user.IdUsuario}", new { user.IdUsuario });
    }

    private static async Task<IResult> ListUsers(Db db, int? page, int? pageSize, CancellationToken ct)
    {
        var currentPage = page ?? 1;
        var size = pageSize ?? 20;
        if (currentPage < 1 || size is < 1 or > 100)
            throw new ApiException(StatusCodes.Status400BadRequest, "page deve ser positivo e pageSize deve estar entre 1 e 100.");

        await using var connection = await db.Open(ct);
        using var results = await connection.QueryMultipleAsync(new CommandDefinition($"""
            SELECT {PublicColumns} FROM dbo.USUARIOS
            ORDER BY IdUsuario OFFSET @offset ROWS FETCH NEXT @size ROWS ONLY;
            SELECT COUNT_BIG(*) FROM dbo.USUARIOS;
            """, new { offset = (currentPage - 1L) * size, size }, cancellationToken: ct));
        var items = (await results.ReadAsync<UserRecord>()).Select(UserResponse.From).ToArray();
        var total = await results.ReadSingleAsync<long>();
        return Results.Ok(new { items, total, page = currentPage, pageSize = size });
    }

    private static async Task<IResult> GetUser(int id, Db db, CancellationToken ct)
    {
        if (id <= 0) throw new ApiException(StatusCodes.Status400BadRequest, "Identificador inválido.");
        await using var connection = await db.Open(ct);
        var user = await connection.QuerySingleOrDefaultAsync<UserRecord>(new CommandDefinition(
            $"SELECT {PublicColumns} FROM dbo.USUARIOS WHERE IdUsuario = @id;",
            new { id }, cancellationToken: ct));
        if (user is null) throw new ApiException(StatusCodes.Status404NotFound, "Usuário não encontrado.");
        return Results.Ok(UserResponse.From(user));
    }

    private static async Task<IResult> SetActive(
        int id, SetUserActiveRequest request, ClaimsPrincipal principal, Db db, CancellationToken ct)
    {
        if (id <= 0) throw new ApiException(StatusCodes.Status400BadRequest, "Identificador inválido.");
        if (request.Ativo is null)
            throw new ApiException(StatusCodes.Status400BadRequest, "Informe o campo ativo como true ou false.");
        if (!request.Ativo.Value && id == principal.UserId())
            throw new ApiException(StatusCodes.Status409Conflict, "Você não pode desativar sua própria conta.");

        await using var connection = await db.Open(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);

        // Todos os pedidos de alteração bloqueiam os administradores na mesma ordem.
        // Isso impede que duas requisições removam simultaneamente os últimos administradores.
        var activeAdministrators = await connection.ExecuteScalarAsync<int>(new CommandDefinition("""
            SELECT COUNT(*) FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK)
            WHERE Perfil = 'ADMINISTRADOR' AND Ativo = 1;
            """, transaction: transaction, cancellationToken: ct));
        var user = await connection.QuerySingleOrDefaultAsync<UserRecord>(new CommandDefinition("""
            SELECT IdUsuario, Perfil, Ativo FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK)
            WHERE IdUsuario = @id;
            """, new { id }, transaction, cancellationToken: ct));
        if (user is null) throw new ApiException(StatusCodes.Status404NotFound, "Usuário não encontrado.");
        if (!request.Ativo.Value && user.Ativo && user.Perfil == Profiles.Administrator && activeAdministrators <= 1)
            throw new ApiException(StatusCodes.Status409Conflict, "É necessário manter ao menos um administrador ativo.");

        if (user.Ativo != request.Ativo.Value)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                "UPDATE dbo.USUARIOS SET Ativo = @ativo WHERE IdUsuario = @id;",
                new { id, ativo = request.Ativo.Value }, transaction, cancellationToken: ct));
            await Db.Audit(connection, transaction, principal.UserId(),
                request.Ativo.Value ? "USUARIO_ATIVADO" : "USUARIO_DESATIVADO",
                JsonSerializer.Serialize(new { IdUsuario = id }));
        }
        await transaction.CommitAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> DeleteStudent(
        int id, ClaimsPrincipal principal, Db db, CancellationToken ct)
    {
        if (id <= 0) throw new ApiException(StatusCodes.Status400BadRequest, "Identificador inválido.");

        await using var connection = await db.Open(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var student = await connection.QuerySingleOrDefaultAsync<UserRecord>(new CommandDefinition("""
            SELECT IdUsuario, Nome, Username, Perfil FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK)
            WHERE IdUsuario = @id;
            """, new { id }, transaction, cancellationToken: ct));
        if (student is null)
            throw new ApiException(StatusCodes.Status404NotFound, "Aluno não encontrado.");
        if (student.Perfil != Profiles.Reader)
            throw new ApiException(StatusCodes.Status409Conflict, "Somente contas de aluno podem ser excluídas.");

        var hasLoans = await connection.ExecuteScalarAsync<bool>(new CommandDefinition("""
            SELECT CASE WHEN EXISTS (
                SELECT 1 FROM dbo.EMPRESTIMOS WITH (UPDLOCK, HOLDLOCK)
                WHERE IdUsuario = @id OR IdOperador = @id
            ) THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END;
            """, new { id }, transaction, cancellationToken: ct));
        if (hasLoans)
            throw new ApiException(StatusCodes.Status409Conflict,
                "Este aluno possui histórico de empréstimos e não pode ser excluído. Desative a conta para preservar o histórico.");

        // Os registros de auditoria permanecem, mas deixam de apontar para a conta removida.
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.TBL_LOG_SISTEMA SET IdUsuario = NULL WHERE IdUsuario = @id;",
            new { id }, transaction, cancellationToken: ct));
        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM dbo.USUARIOS WHERE IdUsuario = @id;",
            new { id }, transaction, cancellationToken: ct));
        await Db.Audit(connection, transaction, principal.UserId(), "ALUNO_EXCLUIDO",
            JsonSerializer.Serialize(new { IdUsuario = id, student.Nome, student.Username }));
        await transaction.CommitAsync(ct);
        return Results.NoContent();
    }

    private static ApiException InvalidCredentials() =>
        new(StatusCodes.Status401Unauthorized, "Username ou senha inválidos.");
}
