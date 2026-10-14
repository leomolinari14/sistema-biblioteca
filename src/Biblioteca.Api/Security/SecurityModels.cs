using System.Security.Claims;
using Biblioteca.Api.Infrastructure;

namespace Biblioteca.Api.Security;

public static class Profiles
{
    public const string Administrator = "ADMINISTRADOR";
    public const string Librarian = "BIBLIOTECARIO";
    public const string Reader = "LEITOR";

    public static bool IsValid(string value) =>
        value is Administrator or Librarian or Reader;
}

public sealed class UserRecord
{
    public int IdUsuario { get; set; }
    public string Nome { get; set; } = "";
    public string? Cpf { get; set; }
    public string Email { get; set; } = "";
    public string Username { get; set; } = "";
    public string SenhaHash { get; set; } = "";
    public string Perfil { get; set; } = "";
    public bool Ativo { get; set; }
    public DateTime DataCadastro { get; set; }
}

public sealed record LoginRequest(string? Username, string? Senha);
public sealed record CreateUserRequest(
    string? Nome, string? Email, string? Username, string? Senha,
    string? Cpf = null, string? Perfil = null);
public sealed record SetUserActiveRequest(bool? Ativo);

public sealed record UserResponse(
    int IdUsuario, string Nome, string? Cpf, string Email, string Username,
    string Perfil, bool Ativo, DateTime DataCadastro)
{
    public static UserResponse From(UserRecord user) => new(
        user.IdUsuario, user.Nome, user.Cpf, user.Email, user.Username,
        user.Perfil, user.Ativo, DateTime.SpecifyKind(user.DataCadastro, DateTimeKind.Utc));
}

public static class CurrentUser
{
    public static int UserId(this ClaimsPrincipal principal)
    {
        if (!int.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var id) || id <= 0)
            throw new ApiException(StatusCodes.Status401Unauthorized, "Sessão inválida. Entre novamente.");
        return id;
    }
}
