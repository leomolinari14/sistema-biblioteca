/* ================================================================
   api.js — camada de comunicação com a API REST
   Base URL configurável; token JWT armazenado em memória.
   ================================================================ */

// A interface agora é servida pela própria API no mesmo endereço.
const API_BASE = '';

let _token = null;

const Api = (() => {
  function setToken(t) { _token = t; }
  function clearToken() { _token = null; }
  function hasToken() { return !!_token; }

  async function request(method, path, body) {
    const headers = { 'Content-Type': 'application/json' };
    if (_token) headers['Authorization'] = 'Bearer ' + _token;

    const res = await fetch(API_BASE + path, {
      method,
      headers,
      body: body != null ? JSON.stringify(body) : undefined,
    });

    if (res.status === 204) return null;

    const text = await res.text();
    let data;
    try { data = JSON.parse(text); } catch { data = { detail: text }; }

    if (!res.ok) {
      const msg = data?.detail || data?.title || 'Erro desconhecido.';
      const err = new Error(msg);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  const get    = (path)        => request('GET',    path);
  const post   = (path, body)  => request('POST',   path, body);
  const put    = (path, body)  => request('PUT',    path, body);
  const patch  = (path, body)  => request('PATCH',  path, body);
  const del    = (path)        => request('DELETE', path);

  // ── Auth ────────────────────────────────────────────────────────
  async function login(username, senha) {
    const data = await post('/api/v1/auth/login', { username, senha });
    setToken(data.accessToken);
    return data;
  }
  const me = () => get('/api/v1/auth/me');
  const cadastrarAluno = (body) => post('/api/v1/auth/cadastro-aluno', body);

  // ── Catálogo ────────────────────────────────────────────────────
  const livros = (q, idCategoria, page, pageSize) => {
    const qs = new URLSearchParams();
    if (q) qs.set('q', q);
    if (idCategoria) qs.set('idCategoria', idCategoria);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/livros?' + qs);
  };
  const livro = (id) => get('/api/v1/livros/' + id);
  const criarLivro = (b) => post('/api/v1/livros', b);
  const atualizarLivro = (id, b) => put('/api/v1/livros/' + id, b);
  const excluirLivro = (id) => del('/api/v1/livros/' + id);

  const categorias = (q, page, pageSize) => {
    const qs = new URLSearchParams();
    if (q) qs.set('q', q);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/categorias?' + qs);
  };
  const editoras = (q, page, pageSize) => {
    const qs = new URLSearchParams();
    if (q) qs.set('q', q);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/editoras?' + qs);
  };
  const autores = (q, page, pageSize) => {
    const qs = new URLSearchParams();
    if (q) qs.set('q', q);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/autores?' + qs);
  };

  // ── Exemplares ──────────────────────────────────────────────────
  const exemplares = (idLivro, situacao, page, pageSize) => {
    const qs = new URLSearchParams();
    if (idLivro) qs.set('idLivro', idLivro);
    if (situacao) qs.set('situacao', situacao);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/exemplares?' + qs);
  };
  const exemplarPorCodigo = (codigo) => get('/api/v1/exemplares/codigo/' + encodeURIComponent(codigo));
  const criarExemplar = (b) => post('/api/v1/exemplares', b);
  const alterarSituacaoExemplar = (id, situacao) => patch('/api/v1/exemplares/' + id + '/situacao', { situacao });
  const excluirExemplar = (id) => del('/api/v1/exemplares/' + id);

  // ── Circulação ──────────────────────────────────────────────────
  const selfCheckout = (codigosExemplares) => post('/api/v1/self-checkout/emprestimos', { codigosExemplares });
  const selfReturn = (codigosExemplares) => post('/api/v1/self-checkout/devolucoes', { codigosExemplares });
  const criarEmprestimoBalcao = (idUsuario, codigosExemplares) => post('/api/v1/emprestimos', { idUsuario, codigosExemplares });
  const emprestimo = (id) => get('/api/v1/emprestimos/' + id);
  const meusEmprestimos = (situacao, page, pageSize) => {
    const qs = new URLSearchParams();
    if (situacao) qs.set('situacao', situacao);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/me/emprestimos?' + qs);
  };
  const emprestimos = (idUsuario, situacao, page, pageSize) => {
    const qs = new URLSearchParams();
    if (idUsuario) qs.set('idUsuario', idUsuario);
    if (situacao) qs.set('situacao', situacao);
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/emprestimos?' + qs);
  };
  const registrarDevolucao = (id, idsExemplares) => post('/api/v1/emprestimos/' + id + '/devolucoes', { idsExemplares });

  // ── Configurações ────────────────────────────────────────────────
  const configuracoes = () => get('/api/v1/configuracoes');
  const atualizarConfiguracoes = (b) => put('/api/v1/configuracoes', b);

  // ── Usuários ────────────────────────────────────────────────────
  const usuarios = (page, pageSize) => {
    const qs = new URLSearchParams();
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/usuarios?' + qs);
  };
  const usuario = (id) => get('/api/v1/usuarios/' + id);
  const criarUsuario = (b) => post('/api/v1/usuarios/', b);
  const ativarUsuario = (id, ativo) => patch('/api/v1/usuarios/' + id + '/ativo', { ativo });
  const excluirAluno = (id) => del('/api/v1/usuarios/' + id);

  // ── Auditoria ────────────────────────────────────────────────────
  const auditoria = (page, pageSize) => {
    const qs = new URLSearchParams();
    if (page) qs.set('page', page);
    if (pageSize) qs.set('pageSize', pageSize);
    return get('/api/v1/auditoria?' + qs);
  };

  return {
    setToken, clearToken, hasToken,
    login, me, cadastrarAluno,
    livros, livro, criarLivro, atualizarLivro, excluirLivro,
    categorias, editoras, autores,
    exemplares, exemplarPorCodigo, criarExemplar, alterarSituacaoExemplar, excluirExemplar,
    selfCheckout, selfReturn, criarEmprestimoBalcao,
    emprestimo, meusEmprestimos, emprestimos, registrarDevolucao,
    configuracoes, atualizarConfiguracoes,
    usuarios, usuario, criarUsuario, ativarUsuario, excluirAluno,
    auditoria,
  };
})();
