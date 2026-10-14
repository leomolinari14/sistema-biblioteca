using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Biblioteca.Api.Data;
using Dapper;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.IdentityModel.Tokens;

namespace Biblioteca.Api.Security;

public static class SecurityConfiguration
{
    public static IServiceCollection AddLibrarySecurity(
        this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        var key = configuration["Jwt:Key"];
        if (string.IsNullOrWhiteSpace(key))
        {
            if (!environment.IsDevelopment())
                throw new InvalidOperationException("Configure Jwt:Key com pelo menos 32 caracteres antes de iniciar a API.");

            key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
            Console.WriteLine("AVISO: Jwt:Key não configurada. Chave temporária gerada apenas para Development; sessões expiram ao reiniciar.");
        }
        if (key.Length < 32)
            throw new InvalidOperationException("Jwt:Key deve ter pelo menos 32 caracteres.");

        var settings = new JwtSettings(key);
        services.AddSingleton(settings);
        services.AddSingleton<IPasswordHasher<UserRecord>, PasswordHasher<UserRecord>>();
        services.AddSingleton<TokenService>();
        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.MapInboundClaims = false;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = JwtSettings.Issuer,
                    ValidateAudience = true,
                    ValidAudience = JwtSettings.Audience,
                    ValidateLifetime = true,
                    RequireExpirationTime = true,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = settings.SigningKey,
                    ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                    NameClaimType = ClaimTypes.Name,
                    RoleClaimType = ClaimTypes.Role,
                    ClockSkew = TimeSpan.FromSeconds(15)
                };
                options.Events = new JwtBearerEvents
                {
                    OnTokenValidated = async context =>
                    {
                        var principal = context.Principal;
                        if (!int.TryParse(principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) || id <= 0)
                        {
                            context.Fail("Sessão inválida.");
                            return;
                        }

                        var db = context.HttpContext.RequestServices.GetRequiredService<Db>();
                        await using var connection = await db.Open(context.HttpContext.RequestAborted);
                        var user = await connection.QuerySingleOrDefaultAsync<UserRecord>(new CommandDefinition(
                            "SELECT IdUsuario, Perfil, Ativo FROM dbo.USUARIOS WHERE IdUsuario = @id;",
                            new { id }, cancellationToken: context.HttpContext.RequestAborted));
                        if (user is null || !user.Ativo || user.Perfil != principal!.FindFirstValue(ClaimTypes.Role))
                            context.Fail("Usuário inativo ou perfil alterado. Entre novamente.");
                    }
                };
            });
        services.AddAuthorization(options =>
        {
            options.AddPolicy("Staff", policy => policy.RequireRole(Profiles.Administrator, Profiles.Librarian));
            options.AddPolicy("Admin", policy => policy.RequireRole(Profiles.Administrator));
            options.AddPolicy("Reader", policy => policy.RequireRole(Profiles.Reader));
        });
        return services;
    }
}

public sealed class JwtSettings(string key)
{
    public const string Issuer = "Biblioteca.Api";
    public const string Audience = "Biblioteca.Clientes";
    public const int ExpiresInSeconds = 3600;
    public SymmetricSecurityKey SigningKey { get; } = new(Encoding.UTF8.GetBytes(key));
}

public sealed class TokenService
{
    private readonly JwtSettings _settings;
    private readonly IPasswordHasher<UserRecord> _hasher;
    private readonly UserRecord _dummyUser = new();
    private readonly string _dummyHash;

    public TokenService(JwtSettings settings, IPasswordHasher<UserRecord> hasher)
    {
        _settings = settings;
        _hasher = hasher;
        _dummyHash = hasher.HashPassword(_dummyUser, Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)));
    }

    public PasswordVerificationResult Verify(UserRecord? user, string password) =>
        _hasher.VerifyHashedPassword(user ?? _dummyUser, user?.SenhaHash ?? _dummyHash, password);

    public string Issue(UserRecord user)
    {
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            issuer: JwtSettings.Issuer,
            audience: JwtSettings.Audience,
            claims:
            [
                new Claim(ClaimTypes.NameIdentifier, user.IdUsuario.ToString(System.Globalization.CultureInfo.InvariantCulture)),
                new Claim(ClaimTypes.Name, user.Username),
                new Claim(ClaimTypes.Role, user.Perfil),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString("N"))
            ],
            notBefore: now,
            expires: now.AddSeconds(JwtSettings.ExpiresInSeconds),
            signingCredentials: new SigningCredentials(_settings.SigningKey, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
