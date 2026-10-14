SET NOCOUNT ON;
IF EXISTS (SELECT IdExemplar FROM dbo.ITENS_EMPRESTIMO WHERE DataHoraDevolucao IS NULL GROUP BY IdExemplar HAVING COUNT(*) > 1)
    THROW 52001, N'Exemplar em mais de um empréstimo ativo.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.EXEMPLARES x
    WHERE (x.Situacao = 'EMPRESTADO' AND NOT EXISTS (SELECT 1 FROM dbo.ITENS_EMPRESTIMO i WHERE i.IdExemplar=x.IdExemplar AND i.DataHoraDevolucao IS NULL))
       OR (x.Situacao <> 'EMPRESTADO' AND EXISTS (SELECT 1 FROM dbo.ITENS_EMPRESTIMO i WHERE i.IdExemplar=x.IdExemplar AND i.DataHoraDevolucao IS NULL)))
    THROW 52002, N'Disponibilidade não corresponde aos itens em aberto.', 1;
IF EXISTS (
    SELECT 1 FROM dbo.EMPRESTIMOS e
    WHERE (e.Situacao='ABERTO' AND NOT EXISTS (SELECT 1 FROM dbo.ITENS_EMPRESTIMO i WHERE i.IdEmprestimo=e.IdEmprestimo AND i.DataHoraDevolucao IS NULL))
       OR (e.Situacao='FINALIZADO' AND EXISTS (SELECT 1 FROM dbo.ITENS_EMPRESTIMO i WHERE i.IdEmprestimo=e.IdEmprestimo AND i.DataHoraDevolucao IS NULL)))
    THROW 52003, N'Cabeçalho incompatível com a devolução dos itens.', 1;
IF EXISTS (SELECT 1 FROM dbo.EMPRESTIMOS WHERE Canal='SELF_CHECKOUT' AND IdOperador<>IdUsuario)
    THROW 52004, N'Self-checkout pertence a outro usuário.', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
    THROW 52005, N'Chave estrangeira desabilitada ou não validada.', 1;
PRINT N'OK: cinco invariantes de integridade conferidas no SQL Server.';
