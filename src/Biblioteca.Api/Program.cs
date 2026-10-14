using System.Threading.RateLimiting;
using Biblioteca.Api.Data;
using Biblioteca.Api.Features;
using Biblioteca.Api.Infrastructure;
using Biblioteca.Api.Security;
using Dapper;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<Db>();
builder.Services.AddLibrarySecurity(builder.Configuration, builder.Environment);
builder.Services.AddProblemDetails();
builder.Services.AddLibraryOpenApi();
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow;
    options.SerializerOptions.DictionaryKeyPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
    options.SerializerOptions.Converters.Add(new UtcDateTimeConverter());
});
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = 429;
    options.AddPolicy("login", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "local",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 30, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    if (origins.Length > 0) policy.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod();
}));
var app = builder.Build();
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseMiddleware<ErrorMiddleware>();
app.UseStatusCodePages(async status =>
{
    var code = status.HttpContext.Response.StatusCode;
    await Results.Problem(statusCode: code, title: "Requisição não atendida", detail: code switch
    {
        401 => "Entre com uma conta ativa para continuar.",
        403 => "Seu perfil não tem permissão para esta operação.",
        404 => "Recurso não encontrado.",
        429 => "Muitas tentativas. Aguarde um minuto e tente novamente.",
        _ => "Verifique os dados enviados."
    }).ExecuteAsync(status.HttpContext);
});
if (!app.Environment.IsDevelopment()) { app.UseHsts(); app.UseHttpsRedirection(); }
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapGet("/", (IWebHostEnvironment environment) =>
    Results.File(Path.Combine(environment.WebRootPath, "index.html"), "text/html"))
    .AllowAnonymous().ExcludeFromDescription();
app.MapGet("/api/v1/info", () => Results.Ok(new
{
    sistema = "Biblioteca", versao = "0.2.0", documentacao = "/openapi/v1.json",
    funcionalidades = new[] { "catalogo", "usuarios", "emprestimos", "devolucoes", "self-checkout", "auditoria" }
})).AllowAnonymous().ExcludeFromDescription();
app.MapGet("/health", async (Db db, CancellationToken ct) =>
{
    try
    {
        await using var cn = await db.Open(ct);
        await cn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.CONFIGURACOES");
        return Results.Ok(new { status = "ok", banco = "SQL Server" });
    }
    catch { return Results.Problem(statusCode: 503, title: "Banco indisponível ou não inicializado"); }
}).AllowAnonymous();
if (app.Environment.IsDevelopment()) app.MapOpenApi().AllowAnonymous();
else app.MapOpenApi().RequireAuthorization("Admin");
app.MapLibrarySecurity();
app.MapCatalog();
app.MapCirculation();
await BootstrapAdmin.Initialize(app.Services.GetRequiredService<Db>(), builder.Configuration, CancellationToken.None);
app.Run();
