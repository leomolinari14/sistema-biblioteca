using System.Data;
using Biblioteca.Api.Data;
using Dapper;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;

namespace Biblioteca.Api.Security;

public static class BootstrapAdmin
{
    public static async Task Initialize(Db db, IConfiguration configuration, CancellationToken ct = default)
    {
        var password = configuration["Bootstrap:AdminPassword"];
        if (string.IsNullOrWhiteSpace(password)) return;

        await using var connection = await db.Open(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        var existing = await connection.ExecuteScalarAsync<int>(new CommandDefinition("""
            SELECT COUNT(*) FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK)
            WHERE Perfil = 'ADMINISTRADOR';
            """, transaction: transaction, cancellationToken: ct));
        if (existing > 0)
        {
            await transaction.CommitAsync(ct);
            return;
        }

        UserValidation.ValidatePassword(password);
        var admin = new UserRecord
        {
            Nome = "Administrador",
            Email = "admin@biblioteca.local",
            Username = "admin",
            Perfil = Profiles.Administrator,
            Ativo = true
        };
        admin.SenhaHash = new PasswordHasher<UserRecord>().HashPassword(admin, password);
        try
        {
            admin.IdUsuario = await connection.QuerySingleAsync<int>(new CommandDefinition("""
                INSERT INTO dbo.USUARIOS (Nome, Email, Username, SenhaHash, Perfil, Ativo)
                OUTPUT INSERTED.IdUsuario
                VALUES (@Nome, @Email, @Username, @SenhaHash, @Perfil, 1);
                """, admin, transaction, cancellationToken: ct));
            await Db.Audit(connection, transaction, admin.IdUsuario, "ADMINISTRADOR_INICIAL_CRIADO",
                "Administrador inicial criado por configuração de bootstrap.");
            await transaction.CommitAsync(ct);
        }
        catch (SqlException exception) when (exception.Number is 2601 or 2627)
        {
            throw new InvalidOperationException(
                "Não foi possível criar o administrador inicial: username admin ou e-mail admin@biblioteca.local já está em uso.");
        }
    }
}
