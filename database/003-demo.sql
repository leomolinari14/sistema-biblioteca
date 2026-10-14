/* Opcional: catálogo fictício para demonstração, sem usuários/senhas.
   Reexecuções preservam cadastros, situações e empréstimos existentes. */
USE [BibliotecaCodex_20260930];
GO
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Trava int;
    EXEC @Trava = sys.sp_getapplock @Resource = N'Biblioteca:CatalogoDemo',
        @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 10000;
    IF @Trava < 0 THROW 51002, N'O catálogo de demonstração está sendo preparado. Tente novamente.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.EDITORAS WHERE Nome = N'Editora Biblioteca Demo')
        INSERT dbo.EDITORAS(Nome, Nacionalidade) VALUES (N'Editora Biblioteca Demo', N'Brasileira');
    DECLARE @IdEditora int = (SELECT MIN(IdEditora) FROM dbo.EDITORAS WHERE Nome = N'Editora Biblioteca Demo');

    IF NOT EXISTS (SELECT 1 FROM dbo.CATEGORIAS WHERE Nome = N'Tecnologia')
        INSERT dbo.CATEGORIAS(Nome, Descricao) VALUES (N'Tecnologia', N'Computação, desenvolvimento e bancos de dados.');
    IF NOT EXISTS (SELECT 1 FROM dbo.CATEGORIAS WHERE Nome = N'Literatura')
        INSERT dbo.CATEGORIAS(Nome, Descricao) VALUES (N'Literatura', N'Obras literárias do acervo.');

    IF NOT EXISTS (SELECT 1 FROM dbo.AUTORES WHERE Nome = N'Ana Exemplo')
        INSERT dbo.AUTORES(Nome, Nacionalidade) VALUES (N'Ana Exemplo', N'Brasileira');
    IF NOT EXISTS (SELECT 1 FROM dbo.AUTORES WHERE Nome = N'Bruno Exemplo')
        INSERT dbo.AUTORES(Nome, Nacionalidade) VALUES (N'Bruno Exemplo', N'Brasileira');

    /* Corrige títulos gravados por versões antigas do inicializador que usavam
       a página de código do console em vez de UTF-8. */
    UPDATE dbo.LIVROS
    SET Titulo = N'Banco de Dados na Prática - Demo'
    WHERE IdEditora = @IdEditora
      AND Titulo LIKE N'Banco de Dados na Pr%tica - Demo'
      AND Titulo <> N'Banco de Dados na Prática - Demo';

    UPDATE dbo.LIVROS
    SET Titulo = N'Histórias da Biblioteca - Demo'
    WHERE IdEditora = @IdEditora
      AND Titulo LIKE N'Hist%rias da Biblioteca - Demo'
      AND Titulo <> N'Histórias da Biblioteca - Demo';

    DECLARE @Catalogo TABLE (Titulo nvarchar(250), Categoria nvarchar(100), Autor nvarchar(160), CodigoBase nvarchar(50));
    INSERT @Catalogo(Titulo, Categoria, Autor, CodigoBase) VALUES
        (N'Banco de Dados na Prática - Demo', N'Tecnologia', N'Ana Exemplo', N'DEMO-BD'),
        (N'Construindo APIs - Demo', N'Tecnologia', N'Bruno Exemplo', N'DEMO-API'),
        (N'Histórias da Biblioteca - Demo', N'Literatura', N'Ana Exemplo', N'DEMO-LIT');

    INSERT dbo.LIVROS(IdEditora, IdCategoria, Titulo, Isbn, AnoPublicacao, NumeroEdicao)
    SELECT @IdEditora, c.IdCategoria, d.Titulo, NULL, 2026, 1
    FROM @Catalogo d INNER JOIN dbo.CATEGORIAS c ON c.Nome = d.Categoria
    WHERE NOT EXISTS (SELECT 1 FROM dbo.LIVROS l WHERE l.IdEditora = @IdEditora AND l.Titulo = d.Titulo);

    DECLARE @LivrosDemo TABLE (IdLivro int, Titulo nvarchar(250), Autor nvarchar(160), CodigoBase nvarchar(50));
    INSERT @LivrosDemo(IdLivro, Titulo, Autor, CodigoBase)
    SELECT (SELECT MIN(l.IdLivro) FROM dbo.LIVROS l WHERE l.IdEditora = @IdEditora AND l.Titulo = d.Titulo),
        d.Titulo, d.Autor, d.CodigoBase FROM @Catalogo d;

    INSERT dbo.LIVROS_AUTORES(IdLivro, IdAutor)
    SELECT d.IdLivro, a.IdAutor FROM @LivrosDemo d
    CROSS APPLY (SELECT MIN(IdAutor) AS IdAutor FROM dbo.AUTORES WHERE Nome = d.Autor) a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.LIVROS_AUTORES la WHERE la.IdLivro = d.IdLivro AND la.IdAutor = a.IdAutor);

    INSERT dbo.EXEMPLARES(IdLivro, CodigoTombo, Situacao, DataAquisicao)
    SELECT d.IdLivro, CONCAT(d.CodigoBase, N'-00', n.Numero), 'DISPONIVEL', CONVERT(date, SYSUTCDATETIME())
    FROM @LivrosDemo d CROSS JOIN (VALUES (1), (2)) n(Numero)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.EXEMPLARES e WHERE e.CodigoTombo = CONCAT(d.CodigoBase, N'-00', n.Numero));

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
