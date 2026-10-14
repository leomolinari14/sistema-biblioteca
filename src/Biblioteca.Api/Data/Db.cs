using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace Biblioteca.Api.Data;

public sealed class Db(IConfiguration configuration)
{
    public async Task<SqlConnection> Open(CancellationToken ct = default)
    {
        var connection = new SqlConnection(configuration.GetConnectionString("Biblioteca")
            ?? throw new InvalidOperationException("Configure ConnectionStrings:Biblioteca."));
        try { await connection.OpenAsync(ct); return connection; }
        catch { await connection.DisposeAsync(); throw; }
    }

    public static Task Audit(SqlConnection connection, SqlTransaction? tx, int? actor,
        string evento, string? details = null) => connection.ExecuteAsync(
            "dbo.SP_REG_LOG_SISTEMA",
            new { IdUsuario = actor, Evento = evento, Detalhes = details },
            transaction: tx, commandType: CommandType.StoredProcedure);
}
