using System.Net.Mail;
using System.Text.RegularExpressions;
using Biblioteca.Api.Infrastructure;

namespace Biblioteca.Api.Security;

public static partial class UserValidation
{
    public static UserRecord Validate(CreateUserRequest request)
    {
        var name = request.Nome?.Trim() ?? "";
        var email = request.Email?.Trim().ToLowerInvariant() ?? "";
        var username = request.Username?.Trim() ?? "";
        var profile = request.Perfil?.Trim().ToUpperInvariant() ?? Profiles.Reader;
        if (name.Length is < 2 or > 160)
            throw BadRequest("Nome deve ter entre 2 e 160 caracteres.");
        if (email.Length > 254 || !MailAddress.TryCreate(email, out var address) || address.Address != email)
            throw BadRequest("Informe um e-mail válido com até 254 caracteres.");
        if (username.Length is < 3 or > 80 || !UsernamePattern().IsMatch(username))
            throw BadRequest("Username deve ter de 3 a 80 caracteres: letras, números, ponto, hífen ou sublinhado.");
        ValidatePassword(request.Senha);
        if (!Profiles.IsValid(profile))
            throw BadRequest("Perfil deve ser ADMINISTRADOR, BIBLIOTECARIO ou LEITOR.");

        var cpf = NormalizeCpf(request.Cpf);
        return new UserRecord
        {
            Nome = name, Email = email, Username = username, Cpf = cpf,
            Perfil = profile, Ativo = true
        };
    }

    public static void ValidatePassword(string? password)
    {
        if (string.IsNullOrWhiteSpace(password) || password.Length is < 10 or > 128)
            throw BadRequest("Senha deve ter entre 10 e 128 caracteres.");
    }

    private static string? NormalizeCpf(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var cpf = value.Trim().Replace(".", "").Replace("-", "");
        if (cpf.Length != 11 || cpf.Any(c => c is < '0' or > '9') || cpf.Distinct().Count() == 1)
            throw BadRequest("Informe um CPF válido, com 11 dígitos.");
        for (var digits = 9; digits <= 10; digits++)
        {
            var sum = 0;
            for (var index = 0; index < digits; index++)
                sum += (cpf[index] - '0') * (digits + 1 - index);
            var remainder = sum % 11;
            var check = remainder < 2 ? 0 : 11 - remainder;
            if (cpf[digits] - '0' != check)
                throw BadRequest("Informe um CPF válido, com 11 dígitos.");
        }
        return cpf;
    }

    private static ApiException BadRequest(string message) => new(StatusCodes.Status400BadRequest, message);

    [GeneratedRegex("^[A-Za-z0-9._-]+$", RegexOptions.CultureInvariant)]
    private static partial Regex UsernamePattern();
}
