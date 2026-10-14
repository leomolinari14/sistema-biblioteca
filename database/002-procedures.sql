USE [BibliotecaCodex_20260930];
GO
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

CREATE OR ALTER PROCEDURE dbo.SP_REG_LOG_SISTEMA
    @IdUsuario int,
    @Evento nvarchar(120),
    @Detalhes nvarchar(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Evento IS NULL OR LEN(LTRIM(RTRIM(@Evento))) = 0
        THROW 51000, N'O evento de auditoria é obrigatório.', 1;

    INSERT INTO dbo.TBL_LOG_SISTEMA(IdUsuario, Evento, Detalhes)
    VALUES (@IdUsuario, @Evento, @Detalhes);
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_CRIAR_EMPRESTIMO
    @IdUsuario int,
    @IdOperador int,
    @Canal varchar(20),
    @CodigosJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IdUsuario IS NULL OR @IdUsuario <= 0 OR @IdOperador IS NULL OR @IdOperador <= 0
        THROW 51000, N'Informe o leitor e o operador do empréstimo.', 1;
    IF @Canal IS NULL OR @Canal NOT IN ('BALCAO', 'SELF_CHECKOUT')
        THROW 51000, N'O canal deve ser BALCAO ou SELF_CHECKOUT.', 1;
    IF @CodigosJson IS NULL OR ISJSON(@CodigosJson) <> 1 OR LEFT(LTRIM(@CodigosJson), 1) <> '['
        THROW 51000, N'Os códigos de tombo devem formar uma lista JSON de textos.', 1;
    IF DATALENGTH(@CodigosJson) > 32000
        THROW 51000, N'A lista de exemplares excede o tamanho permitido.', 1;

    DECLARE @Entrada TABLE (Codigo nvarchar(max), Tipo int);
    INSERT INTO @Entrada(Codigo, Tipo)
        SELECT LTRIM(RTRIM([value])), [type] FROM OPENJSON(@CodigosJson);
    IF NOT EXISTS (SELECT 1 FROM @Entrada)
        THROW 51000, N'Informe ao menos um código de tombo.', 1;
    IF (SELECT COUNT(*) FROM @Entrada) > 100
        THROW 51000, N'Informe no máximo 100 exemplares por solicitação.', 1;
    IF EXISTS (SELECT 1 FROM @Entrada WHERE Tipo <> 1 OR Codigo IS NULL OR LEN(Codigo) = 0 OR DATALENGTH(Codigo) > 120)
        THROW 51000, N'Cada código deve ser um texto não vazio de até 60 caracteres.', 1;
    IF EXISTS (SELECT Codigo FROM @Entrada GROUP BY Codigo HAVING COUNT(*) > 1)
        THROW 51000, N'Não repita o mesmo exemplar na solicitação.', 1;

    DECLARE @Codigos TABLE (CodigoTombo nvarchar(60) NOT NULL PRIMARY KEY);
    INSERT INTO @Codigos(CodigoTombo) SELECT Codigo FROM @Entrada;
    DECLARE @Quantidade int = (SELECT COUNT(*) FROM @Codigos);
    DECLARE @IdEmprestimo bigint;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- A mesma trava é utilizada na devolução. O MVP serializa operações
        -- curtas de circulação, evitando dupla retirada e inversão de travas.
        DECLARE @Trava int;
        EXEC @Trava = sys.sp_getapplock
            @Resource = N'Biblioteca:Circulacao', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @Trava < 0
            THROW 51002, N'A circulação está ocupada. Tente novamente.', 1;

        DECLARE @Agora datetime2(7) = SYSUTCDATETIME();
        DECLARE @PerfilOperador varchar(20), @OperadorAtivo bit;
        SELECT @PerfilOperador = Perfil, @OperadorAtivo = Ativo
        FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK) WHERE IdUsuario = @IdOperador;
        IF @PerfilOperador IS NULL OR @OperadorAtivo <> 1
            THROW 51004, N'O operador não está autorizado a realizar esta operação.', 1;
        IF @Canal = 'SELF_CHECKOUT' AND (@IdUsuario <> @IdOperador OR @PerfilOperador <> 'LEITOR')
            THROW 51004, N'O self-checkout deve ser realizado pelo próprio leitor autenticado.', 1;
        IF @Canal = 'BALCAO' AND @PerfilOperador NOT IN ('ADMINISTRADOR', 'BIBLIOTECARIO')
            THROW 51004, N'Apenas a equipe da biblioteca pode registrar empréstimos no balcão.', 1;

        DECLARE @LeitorAtivo bit;
        SELECT @LeitorAtivo = Ativo FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK) WHERE IdUsuario = @IdUsuario;
        IF @LeitorAtivo IS NULL
            THROW 51001, N'O leitor informado não foi encontrado.', 1;
        IF @LeitorAtivo <> 1
            THROW 51003, N'O cadastro do leitor está inativo.', 1;

        DECLARE @Limite int, @Prazo int, @BloquearAtrasados bit, @SelfCheckout bit;
        SELECT @Limite = LimiteExemplares, @Prazo = PrazoDias,
            @BloquearAtrasados = BloquearAtrasados, @SelfCheckout = SelfCheckoutHabilitado
        FROM dbo.CONFIGURACOES WITH (UPDLOCK, HOLDLOCK) WHERE Id = 1;
        IF @Limite IS NULL
            THROW 51003, N'As regras de circulação ainda não foram configuradas.', 1;
        IF @Canal = 'SELF_CHECKOUT' AND @SelfCheckout <> 1
            THROW 51003, N'O self-checkout está temporariamente desabilitado.', 1;
        IF @BloquearAtrasados = 1 AND EXISTS (
            SELECT 1 FROM dbo.EMPRESTIMOS e WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ITENS_EMPRESTIMO i WITH (UPDLOCK, HOLDLOCK) ON i.IdEmprestimo = e.IdEmprestimo
            WHERE e.IdUsuario = @IdUsuario AND i.DataHoraDevolucao IS NULL AND e.DataHoraPrevista < @Agora)
            THROW 51003, N'O leitor possui devolução em atraso. Procure a equipe da biblioteca.', 1;

        DECLARE @EmAberto int;
        SELECT @EmAberto = COUNT(*) FROM dbo.ITENS_EMPRESTIMO i WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.EMPRESTIMOS e WITH (UPDLOCK, HOLDLOCK) ON e.IdEmprestimo = i.IdEmprestimo
        WHERE e.IdUsuario = @IdUsuario AND i.DataHoraDevolucao IS NULL;
        IF @EmAberto + @Quantidade > @Limite
            THROW 51003, N'A solicitação ultrapassa o limite de exemplares em aberto por leitor.', 1;

        DECLARE @Exemplares TABLE (IdExemplar int NOT NULL PRIMARY KEY, Situacao varchar(20) NOT NULL);
        INSERT INTO @Exemplares(IdExemplar, Situacao)
        SELECT e.IdExemplar, e.Situacao FROM dbo.EXEMPLARES e WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN @Codigos c ON c.CodigoTombo = e.CodigoTombo;
        IF (SELECT COUNT(*) FROM @Exemplares) <> @Quantidade
            THROW 51001, N'Um ou mais códigos de tombo não foram encontrados.', 1;
        IF EXISTS (SELECT 1 FROM @Exemplares WHERE Situacao <> 'DISPONIVEL')
            THROW 51002, N'Um ou mais exemplares não estão disponíveis para empréstimo.', 1;
        IF EXISTS (
            SELECT 1 FROM dbo.ITENS_EMPRESTIMO i WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN @Exemplares x ON x.IdExemplar = i.IdExemplar WHERE i.DataHoraDevolucao IS NULL)
            THROW 51002, N'Um ou mais exemplares já possuem um empréstimo em aberto.', 1;

        INSERT INTO dbo.EMPRESTIMOS(IdUsuario, IdOperador, Canal, Situacao, DataHoraEmprestimo, DataHoraPrevista)
        VALUES (@IdUsuario, @IdOperador, @Canal, 'ABERTO', @Agora, DATEADD(day, @Prazo, @Agora));
        SET @IdEmprestimo = CONVERT(bigint, SCOPE_IDENTITY());

        INSERT INTO dbo.ITENS_EMPRESTIMO(IdEmprestimo, IdExemplar)
        SELECT @IdEmprestimo, IdExemplar FROM @Exemplares;
        UPDATE e SET Situacao = 'EMPRESTADO'
        FROM dbo.EXEMPLARES e INNER JOIN @Exemplares x ON x.IdExemplar = e.IdExemplar;

        DECLARE @Detalhes nvarchar(1000) = CONCAT(N'Empréstimo ', @IdEmprestimo, N'; leitor ', @IdUsuario,
            N'; canal ', @Canal, N'; exemplares ', @Quantidade, N'.');
        EXEC dbo.SP_REG_LOG_SISTEMA @IdUsuario = @IdOperador, @Evento = N'EMPRESTIMO_CRIADO', @Detalhes = @Detalhes;

        COMMIT TRANSACTION;
        SELECT @IdEmprestimo AS IdEmprestimo;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_REGISTRAR_DEVOLUCAO
    @IdEmprestimo bigint,
    @IdOperador int,
    @IdsExemplaresJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IdEmprestimo IS NULL OR @IdEmprestimo <= 0 OR @IdOperador IS NULL OR @IdOperador <= 0
        THROW 51000, N'Informe o empréstimo e o operador da devolução.', 1;
    IF @IdsExemplaresJson IS NULL OR ISJSON(@IdsExemplaresJson) <> 1 OR LEFT(LTRIM(@IdsExemplaresJson), 1) <> '['
        THROW 51000, N'Os identificadores devem formar uma lista JSON de números inteiros.', 1;
    IF DATALENGTH(@IdsExemplaresJson) > 10000
        THROW 51000, N'A lista de devolução excede o tamanho permitido.', 1;

    DECLARE @Entrada TABLE (Valor nvarchar(max), Tipo int);
    INSERT INTO @Entrada(Valor, Tipo) SELECT [value], [type] FROM OPENJSON(@IdsExemplaresJson);
    IF NOT EXISTS (SELECT 1 FROM @Entrada)
        THROW 51000, N'Informe ao menos um exemplar para devolução.', 1;
    IF (SELECT COUNT(*) FROM @Entrada) > 100
        THROW 51000, N'Informe no máximo 100 exemplares por devolução.', 1;
    IF EXISTS (SELECT 1 FROM @Entrada WHERE Tipo <> 2 OR TRY_CONVERT(int, Valor) IS NULL OR TRY_CONVERT(int, Valor) <= 0
        OR Valor LIKE N'%[^0-9]%')
        THROW 51000, N'Cada identificador de exemplar deve ser um número inteiro positivo.', 1;
    IF EXISTS (SELECT TRY_CONVERT(int, Valor) FROM @Entrada GROUP BY TRY_CONVERT(int, Valor) HAVING COUNT(*) > 1)
        THROW 51000, N'Não repita o mesmo exemplar na devolução.', 1;

    DECLARE @Ids TABLE (IdExemplar int NOT NULL PRIMARY KEY);
    INSERT INTO @Ids(IdExemplar) SELECT CONVERT(int, Valor) FROM @Entrada;
    DECLARE @Quantidade int = (SELECT COUNT(*) FROM @Ids);

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Trava int;
        EXEC @Trava = sys.sp_getapplock
            @Resource = N'Biblioteca:Circulacao', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @Trava < 0
            THROW 51002, N'A circulação está ocupada. Tente novamente.', 1;

        DECLARE @Agora datetime2(7) = SYSUTCDATETIME();
        DECLARE @PerfilOperador varchar(20), @OperadorAtivo bit;
        SELECT @PerfilOperador = Perfil, @OperadorAtivo = Ativo
        FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK) WHERE IdUsuario = @IdOperador;
        IF @PerfilOperador IS NULL OR @OperadorAtivo <> 1 OR @PerfilOperador NOT IN ('ADMINISTRADOR', 'BIBLIOTECARIO')
            THROW 51004, N'Apenas a equipe da biblioteca pode registrar devoluções.', 1;

        DECLARE @Situacao varchar(20);
        SELECT @Situacao = Situacao FROM dbo.EMPRESTIMOS WITH (UPDLOCK, HOLDLOCK) WHERE IdEmprestimo = @IdEmprestimo;
        IF @Situacao IS NULL
            THROW 51001, N'O empréstimo informado não foi encontrado.', 1;
        IF @Situacao <> 'ABERTO'
            THROW 51002, N'Este empréstimo já foi finalizado.', 1;

        DECLARE @Itens TABLE (IdExemplar int NOT NULL PRIMARY KEY, DataHoraDevolucao datetime2(7) NULL);
        INSERT INTO @Itens(IdExemplar, DataHoraDevolucao)
        SELECT i.IdExemplar, i.DataHoraDevolucao FROM dbo.ITENS_EMPRESTIMO i WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN @Ids x ON x.IdExemplar = i.IdExemplar WHERE i.IdEmprestimo = @IdEmprestimo;
        IF (SELECT COUNT(*) FROM @Itens) <> @Quantidade
            THROW 51000, N'Um ou mais exemplares não pertencem ao empréstimo informado.', 1;
        IF EXISTS (SELECT 1 FROM @Itens WHERE DataHoraDevolucao IS NOT NULL)
            THROW 51002, N'Um ou mais exemplares já foram devolvidos.', 1;

        -- Lê e bloqueia os exemplares antes de alterar o vínculo de circulação.
        DECLARE @Exemplares TABLE (IdExemplar int NOT NULL PRIMARY KEY, Situacao varchar(20) NOT NULL);
        INSERT INTO @Exemplares(IdExemplar, Situacao)
        SELECT e.IdExemplar, e.Situacao FROM dbo.EXEMPLARES e WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN @Ids x ON x.IdExemplar = e.IdExemplar;
        IF EXISTS (SELECT 1 FROM @Exemplares WHERE Situacao <> 'EMPRESTADO')
            THROW 51002, N'A situação do exemplar é incompatível com o empréstimo. Solicite revisão do cadastro.', 1;

        UPDATE i SET DataHoraDevolucao = @Agora
        FROM dbo.ITENS_EMPRESTIMO i INNER JOIN @Ids x ON x.IdExemplar = i.IdExemplar
        WHERE i.IdEmprestimo = @IdEmprestimo;
        UPDATE e SET Situacao = 'DISPONIVEL'
        FROM dbo.EXEMPLARES e INNER JOIN @Ids x ON x.IdExemplar = e.IdExemplar;

        IF NOT EXISTS (SELECT 1 FROM dbo.ITENS_EMPRESTIMO WITH (UPDLOCK, HOLDLOCK)
            WHERE IdEmprestimo = @IdEmprestimo AND DataHoraDevolucao IS NULL)
            UPDATE dbo.EMPRESTIMOS SET Situacao = 'FINALIZADO', DataHoraDevolucao = @Agora
            WHERE IdEmprestimo = @IdEmprestimo;

        DECLARE @Detalhes nvarchar(1000) = CONCAT(N'Empréstimo ', @IdEmprestimo, N'; exemplares devolvidos ', @Quantidade, N'.');
        EXEC dbo.SP_REG_LOG_SISTEMA @IdUsuario = @IdOperador, @Evento = N'DEVOLUCAO_REGISTRADA', @Detalhes = @Detalhes;

        COMMIT TRANSACTION;
        SELECT @IdEmprestimo AS IdEmprestimo;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.SP_REGISTRAR_AUTODEVOLUCAO
    @IdUsuario int,
    @CodigosJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IdUsuario IS NULL OR @IdUsuario <= 0
        THROW 51000, N'Informe o aluno da devolução.', 1;
    IF @CodigosJson IS NULL OR ISJSON(@CodigosJson) <> 1 OR LEFT(LTRIM(@CodigosJson), 1) <> '['
        THROW 51000, N'Os códigos devem formar uma lista JSON de textos.', 1;
    IF DATALENGTH(@CodigosJson) > 20000
        THROW 51000, N'A lista de devolução excede o tamanho permitido.', 1;

    DECLARE @Entrada TABLE (Valor nvarchar(max), Tipo int);
    INSERT INTO @Entrada(Valor, Tipo) SELECT [value], [type] FROM OPENJSON(@CodigosJson);
    IF NOT EXISTS (SELECT 1 FROM @Entrada)
        THROW 51000, N'Informe ao menos um código para devolução.', 1;
    IF (SELECT COUNT(*) FROM @Entrada) > 100
        THROW 51000, N'Informe no máximo 100 códigos por devolução.', 1;
    IF EXISTS (SELECT 1 FROM @Entrada WHERE Tipo <> 1 OR LEN(LTRIM(RTRIM(Valor))) NOT BETWEEN 1 AND 60)
        THROW 51000, N'Cada código deve ser um texto entre 1 e 60 caracteres.', 1;
    IF EXISTS (SELECT LTRIM(RTRIM(Valor)) FROM @Entrada GROUP BY LTRIM(RTRIM(Valor)) HAVING COUNT(*) > 1)
        THROW 51000, N'Não repita o mesmo exemplar na devolução.', 1;

    DECLARE @Codigos TABLE (CodigoTombo nvarchar(60) NOT NULL PRIMARY KEY);
    INSERT INTO @Codigos(CodigoTombo) SELECT LTRIM(RTRIM(Valor)) FROM @Entrada;
    DECLARE @Quantidade int = (SELECT COUNT(*) FROM @Codigos);

    DECLARE @Devolucoes TABLE (
        IdEmprestimo bigint NOT NULL,
        IdExemplar int NOT NULL PRIMARY KEY,
        CodigoTombo nvarchar(60) NOT NULL,
        Titulo nvarchar(250) NOT NULL
    );

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Trava int;
        EXEC @Trava = sys.sp_getapplock
            @Resource = N'Biblioteca:Circulacao', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @Trava < 0
            THROW 51002, N'A circulação está ocupada. Tente novamente.', 1;

        DECLARE @Perfil varchar(20), @Ativo bit;
        SELECT @Perfil = Perfil, @Ativo = Ativo
        FROM dbo.USUARIOS WITH (UPDLOCK, HOLDLOCK) WHERE IdUsuario = @IdUsuario;
        IF @Perfil <> 'LEITOR' OR @Ativo <> 1
            THROW 51004, N'A auto devolução exige uma conta de aluno ativa.', 1;

        INSERT INTO @Devolucoes(IdEmprestimo, IdExemplar, CodigoTombo, Titulo)
        SELECT emp.IdEmprestimo, ex.IdExemplar, ex.CodigoTombo, livro.Titulo
        FROM @Codigos cod
        INNER JOIN dbo.EXEMPLARES ex WITH (UPDLOCK, HOLDLOCK) ON ex.CodigoTombo = cod.CodigoTombo
        INNER JOIN dbo.ITENS_EMPRESTIMO item WITH (UPDLOCK, HOLDLOCK)
            ON item.IdExemplar = ex.IdExemplar AND item.DataHoraDevolucao IS NULL
        INNER JOIN dbo.EMPRESTIMOS emp WITH (UPDLOCK, HOLDLOCK)
            ON emp.IdEmprestimo = item.IdEmprestimo AND emp.IdUsuario = @IdUsuario AND emp.Situacao = 'ABERTO'
        INNER JOIN dbo.LIVROS livro ON livro.IdLivro = ex.IdLivro;

        IF (SELECT COUNT(*) FROM @Devolucoes) <> @Quantidade
            THROW 51002, N'Um ou mais códigos não estão emprestados na sua conta.', 1;
        IF EXISTS (
            SELECT 1 FROM @Devolucoes d
            INNER JOIN dbo.EXEMPLARES ex ON ex.IdExemplar = d.IdExemplar
            WHERE ex.Situacao <> 'EMPRESTADO'
        )
            THROW 51002, N'A situação de um exemplar é incompatível com a devolução. Procure a equipe da biblioteca.', 1;

        DECLARE @Agora datetime2(7) = SYSUTCDATETIME();
        UPDATE item SET DataHoraDevolucao = @Agora
        FROM dbo.ITENS_EMPRESTIMO item
        INNER JOIN @Devolucoes d
            ON d.IdEmprestimo = item.IdEmprestimo AND d.IdExemplar = item.IdExemplar
        WHERE item.DataHoraDevolucao IS NULL;

        UPDATE ex SET Situacao = 'DISPONIVEL'
        FROM dbo.EXEMPLARES ex INNER JOIN @Devolucoes d ON d.IdExemplar = ex.IdExemplar;

        UPDATE emp SET Situacao = 'FINALIZADO', DataHoraDevolucao = @Agora
        FROM dbo.EMPRESTIMOS emp
        WHERE emp.IdEmprestimo IN (SELECT DISTINCT IdEmprestimo FROM @Devolucoes)
          AND NOT EXISTS (
              SELECT 1 FROM dbo.ITENS_EMPRESTIMO pendente WITH (UPDLOCK, HOLDLOCK)
              WHERE pendente.IdEmprestimo = emp.IdEmprestimo AND pendente.DataHoraDevolucao IS NULL
          );

        DECLARE @Detalhes nvarchar(1000) = CONCAT(N'Auto devolução; aluno ', @IdUsuario,
            N'; exemplares devolvidos ', @Quantidade, N'.');
        EXEC dbo.SP_REG_LOG_SISTEMA @IdUsuario = @IdUsuario,
            @Evento = N'AUTODEVOLUCAO_REGISTRADA', @Detalhes = @Detalhes;

        COMMIT TRANSACTION;
        SELECT IdEmprestimo, IdExemplar, CodigoTombo, Titulo
        FROM @Devolucoes ORDER BY CodigoTombo;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
