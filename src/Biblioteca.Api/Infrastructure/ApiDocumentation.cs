using Microsoft.OpenApi;

namespace Biblioteca.Api.Infrastructure;

public static class ApiDocumentation
{
    public static IServiceCollection AddLibraryOpenApi(this IServiceCollection services)
    {
        services.AddOpenApi(options => options.AddDocumentTransformer((document, context, ct) =>
        {
            document.Info = new OpenApiInfo
            {
                Title = "Biblioteca - API e self-checkout", Version = "0.2.0",
                Description = "Catálogo, perfis, empréstimos de balcão, autoempréstimo e devoluções. Horários são UTC. Autentique em /api/v1/auth/login e envie o accessToken como Bearer."
            };
            document.Components ??= new OpenApiComponents();
            document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
            document.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http, Scheme = "bearer", BearerFormat = "JWT",
                Description = "Token retornado pelo login, válido por 60 minutos."
            };
            foreach (var (path, item) in document.Paths)
            {
                if (!path.StartsWith("/api/v1/") || path == "/api/v1/auth/login") continue;
                if (item.Operations is null) continue;
                foreach (var operation in item.Operations.Values)
                {
                    operation.Security = [new OpenApiSecurityRequirement
                    {
                        [new OpenApiSecuritySchemeReference("Bearer", document)] = []
                    }];
                }
            }
            return Task.CompletedTask;
        }));
        return services;
    }
}
