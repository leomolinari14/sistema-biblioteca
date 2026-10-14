using Microsoft.Data.SqlClient;

namespace Biblioteca.Api.Infrastructure;

public sealed class ApiException(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
}

public sealed class ErrorMiddleware(RequestDelegate next, ILogger<ErrorMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try { await next(context); }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
        catch (Exception ex)
        {
            var (status, detail) = ex switch
            {
                ApiException api => (api.Status, api.Message),
                BadHttpRequestException bad => (bad.StatusCode, "Verifique o formato dos dados enviados."),
                SqlException { Number: 51000 } sql => (400, sql.Message),
                SqlException { Number: 51001 } sql => (404, sql.Message),
                SqlException { Number: 51002 } sql => (409, sql.Message),
                SqlException { Number: 51003 } sql => (422, sql.Message),
                SqlException { Number: 51004 } sql => (403, sql.Message),
                SqlException { Number: 2601 or 2627 } => (409, "Já existe um registro com estes dados únicos."),
                SqlException { Number: 547 } => (422, "O registro relacionado não existe ou uma regra do banco foi violada."),
                SqlException { Number: 1205 or -2 } => (409, "A operação concorreu com outra. Consulte a situação e tente novamente."),
                _ => (500, "Não foi possível concluir a operação. Informe o identificador desta requisição ao suporte.")
            };
            if (status >= 500) logger.LogError(ex, "Falha {TraceId}", context.TraceIdentifier);
            if (!context.Response.HasStarted)
                await Results.Problem(statusCode: status, title: status >= 500 ? "Falha interna" : "Operação não concluída",
                    detail: detail, extensions: new Dictionary<string, object?> { ["traceId"] = context.TraceIdentifier }).ExecuteAsync(context);
        }
    }
}

public static class Guard
{
    public static string Text(string? value, string field, int max)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Trim().Length > max)
            throw new ApiException(400, $"{field}: informe entre 1 e {max} caracteres.");
        return value.Trim();
    }
    public static string? Optional(string? value, string field, int max)
        => string.IsNullOrWhiteSpace(value) ? null : Text(value, field, max);
    public static void That(bool condition, string message)
    {
        if (!condition) throw new ApiException(400, message);
    }
    public static (int Page, int Size, int Offset) Paging(int? page, int? pageSize)
    {
        var p = page ?? 1; var size = pageSize ?? 20;
        That(p is >= 1 and <= 100000 && size is >= 1 and <= 100, "Página deve ser positiva e pageSize deve estar entre 1 e 100.");
        return (p, size, (p - 1) * size);
    }
}
