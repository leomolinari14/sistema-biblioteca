/* ================================================================
   app.js — lógica da SPA Biblioteca
   Propriedades da API em camelCase (ASP.NET Core default)
   ================================================================ */

'use strict';

// ── Estado global ────────────────────────────────────────────────
const State = {
  user: null,   // { idUsuario, nome, perfil, username }
  section: null,
};

// ── Perfis ───────────────────────────────────────────────────────
const isAdmin  = () => State.user?.perfil === 'ADMINISTRADOR';
const isStaff  = () => State.user?.perfil === 'ADMINISTRADOR' || State.user?.perfil === 'BIBLIOTECARIO';
const isReader = () => State.user?.perfil === 'LEITOR';

// ── Helpers DOM ──────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
};
function show(id)  { $(id)?.classList.remove('hidden'); }
function hide(id)  { $(id)?.classList.add('hidden'); }
function showErr(id, msg)  { const e = $(id); if (e) { e.textContent = msg; e.className = 'alert alert-error'; e.classList.remove('hidden'); } }
function showOk(id, msg)   { const e = $(id); if (e) { e.textContent = msg; e.className = 'alert alert-success'; e.classList.remove('hidden'); } }
function clearAlert(id)    { hide(id); }

// ── Formatadores ─────────────────────────────────────────────────
function fmtDate(str) {
  if (!str) return '—';
  const d = new Date(str);
  return d.toLocaleDateString('pt-BR');
}
function fmtDatetime(str) {
  if (!str) return '—';
  const d = new Date(str);
  return d.toLocaleDateString('pt-BR') + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}
function situacaoPill(s) {
  const map = {
    ABERTO:      ['pill-open',     'Aberto'],
    FINALIZADO:  ['pill-done',     'Finalizado'],
    DISPONIVEL:  ['pill-avail',    'Disponível'],
    EMPRESTADO:  ['pill-borrowed', 'Emprestado'],
    MANUTENCAO:  ['pill-maint',    'Manutenção'],
    INATIVO:     ['pill-inactive', 'Inativo'],
  };
  const [cls, label] = map[s] || ['pill-inactive', s];
  return `<span class="pill ${cls}">${label}</span>`;
}
function perfilLabel(p) {
  return { ADMINISTRADOR: 'Admin', BIBLIOTECARIO: 'Bibliotecário', LEITOR: 'Aluno' }[p] || p;
}

// ── Helper: busca propriedade case-insensitive ──────────────────
// A API usa DictionaryKeyPolicy camelCase para objetos Dapper (dynamic/ExpandoObject),
// mas em alguns cenários as chaves podem vir em PascalCase. Este helper garante resiliência.
function prop(obj, name) {
  if (!obj) return undefined;
  // Tenta exato
  if (name in obj) return obj[name];
  // Tenta camelCase
  const camel = name[0].toLowerCase() + name.slice(1);
  if (camel in obj) return obj[camel];
  // Tenta PascalCase
  const pascal = name[0].toUpperCase() + name.slice(1);
  if (pascal in obj) return obj[pascal];
  return undefined;
}

// ── Navegação ────────────────────────────────────────────────────
const NAV_ITEMS = [
  { id: 'home',              label: 'Início',            icon: 'bi-house',              roles: ['all'] },
  { id: 'self-checkout',     label: 'Self-Checkout',     icon: 'bi-upc-scan',           roles: ['LEITOR'] },
  { id: 'meus-emprestimos',  label: 'Meus Empréstimos',  icon: 'bi-journal-text',       roles: ['LEITOR'] },
  { id: 'catalogo',          label: 'Catálogo',          icon: 'bi-book',               roles: ['all'] },
  { id: 'emprestimos',       label: 'Empréstimos',       icon: 'bi-arrow-left-right',   roles: ['ADMINISTRADOR', 'BIBLIOTECARIO'] },
  { id: 'exemplares',        label: 'Exemplares',        icon: 'bi-bookmark',           roles: ['ADMINISTRADOR', 'BIBLIOTECARIO'] },
  { id: 'usuarios',          label: 'Alunos e usuários', icon: 'bi-people',             roles: ['ADMINISTRADOR', 'BIBLIOTECARIO'] },
  { id: 'configuracoes',     label: 'Configurações',     icon: 'bi-gear',               roles: ['ADMINISTRADOR'] },
  { id: 'auditoria',         label: 'Auditoria',         icon: 'bi-shield-check',       roles: ['ADMINISTRADOR'] },
];

function buildNav() {
  const ul = $('nav-menu');
  ul.innerHTML = '';
  const perfil = State.user?.perfil;
  NAV_ITEMS.forEach(item => {
    if (!item.roles.includes('all') && !item.roles.includes(perfil)) return;
    const li = document.createElement('li');
    const btn = el('button', 'nav-item');
    btn.dataset.section = item.id;
    btn.innerHTML = `<i class="bi ${item.icon}"></i>${item.label}`;
    btn.addEventListener('click', () => navigateTo(item.id));
    li.appendChild(btn);
    ul.appendChild(li);
  });
}

function navigateTo(sectionId) {
  document.querySelectorAll('.nav-item').forEach(b => {
    b.classList.toggle('active', b.dataset.section === sectionId);
  });
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  const sec = $('sec-' + sectionId);
  if (sec) sec.classList.add('active');

  const item = NAV_ITEMS.find(i => i.id === sectionId);
  if (item) $('page-title').textContent = item.label;

  $('sidebar').classList.remove('open');
  State.section = sectionId;
  onSectionLoad(sectionId);
}

function onSectionLoad(id) {
  switch (id) {
    case 'home':              loadHome(); break;
    case 'self-checkout':     initSelfCheckout(); break;
    case 'meus-emprestimos':  loadMeusEmprestimos(1); break;
    case 'catalogo':          loadCatalogo(1); break;
    case 'emprestimos':       loadEmprestimos(1); break;
    case 'exemplares':        loadExemplares(1); break;
    case 'usuarios':          loadUsuarios(1); break;
    case 'configuracoes':     loadConfiguracoes(); break;
    case 'auditoria':         loadAuditoria(1); break;
  }
}

// ── Login ────────────────────────────────────────────────────────
$('form-login').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearAlert('login-error');
  const btn = $('btn-login');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Entrando…';
  try {
    const data = await Api.login(
      $('login-username').value.trim(),
      $('login-senha').value,
    );
    State.user = data.usuario;
    enterApp();
  } catch (err) {
    showErr('login-error', err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class="bi bi-box-arrow-in-right"></i> Entrar';
  }
});

$('btn-cadastro-aluno').addEventListener('click', () => {
  openModal('Cadastro de aluno', `
    <form id="form-cadastro-aluno">
      <p class="section-desc">Crie seu acesso de aluno. Este cadastro não concede funções administrativas.</p>
      <div class="form-grid">
        <div class="field form-full">
          <label for="cadastro-nome">Nome completo</label>
          <input id="cadastro-nome" type="text" maxlength="160" autocomplete="name" required />
        </div>
        <div class="field">
          <label for="cadastro-username">Usuário</label>
          <input id="cadastro-username" type="text" minlength="3" maxlength="80" autocomplete="username" required />
        </div>
        <div class="field">
          <label for="cadastro-email">E-mail</label>
          <input id="cadastro-email" type="email" maxlength="254" autocomplete="email" required />
        </div>
        <div class="field form-full">
          <label for="cadastro-cpf">CPF (opcional)</label>
          <input id="cadastro-cpf" type="text" inputmode="numeric" maxlength="14" placeholder="000.000.000-00" />
        </div>
        <div class="field">
          <label for="cadastro-senha">Senha</label>
          <input id="cadastro-senha" type="password" minlength="10" maxlength="128" autocomplete="new-password" required />
        </div>
        <div class="field">
          <label for="cadastro-confirmacao">Confirmar senha</label>
          <input id="cadastro-confirmacao" type="password" minlength="10" maxlength="128" autocomplete="new-password" required />
        </div>
      </div>
      <div id="cadastro-error" class="alert alert-error hidden"></div>
      <div class="modal-actions">
        <button type="button" id="btn-cancelar-cadastro" class="btn btn-outline">Cancelar</button>
        <button type="submit" id="btn-salvar-cadastro" class="btn btn-primary">
          <i class="bi bi-person-check"></i> Criar conta de aluno
        </button>
      </div>
    </form>
  `);

  $('btn-cancelar-cadastro').addEventListener('click', closeModal);
  $('form-cadastro-aluno').addEventListener('submit', async (e) => {
    e.preventDefault();
    clearAlert('cadastro-error');
    const senha = $('cadastro-senha').value;
    if (senha !== $('cadastro-confirmacao').value) {
      showErr('cadastro-error', 'As senhas não coincidem.');
      return;
    }

    const btn = $('btn-salvar-cadastro');
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> Criando…';
    try {
      const username = $('cadastro-username').value.trim();
      await Api.cadastrarAluno({
        nome: $('cadastro-nome').value.trim(),
        username,
        email: $('cadastro-email').value.trim(),
        cpf: $('cadastro-cpf').value.trim() || null,
        senha,
      });
      closeModal();
      $('login-username').value = username;
      $('login-senha').value = '';
      showOk('login-error', 'Cadastro realizado. Agora entre com seu usuário e senha.');
      $('login-senha').focus();
    } catch (err) {
      showErr('cadastro-error', err.message);
      btn.disabled = false;
      btn.innerHTML = '<i class="bi bi-person-check"></i> Criar conta de aluno';
    }
  });
});

function enterApp() {
  $('page-login').classList.remove('active');
  $('page-app').classList.add('active');
  const nome = prop(State.user, 'nome') || prop(State.user, 'Nome') || '—';
  const perfil = prop(State.user, 'perfil') || prop(State.user, 'Perfil') || '';
  $('user-info').innerHTML = `<strong>${nome}</strong>${perfilLabel(perfil)}`;
  buildNav();

  const staff = isStaff();
  if ($('btn-novo-livro')) $('btn-novo-livro').style.display = staff ? '' : 'none';
  if ($('btn-novo-exemplar')) $('btn-novo-exemplar').style.display = staff ? '' : 'none';

  const first = isReader() ? 'self-checkout' : 'home';
  navigateTo(first);
}

$('btn-logout').addEventListener('click', () => {
  Api.clearToken();
  State.user = null;
  $('page-app').classList.remove('active');
  $('page-login').classList.add('active');
  $('login-senha').value = '';
  $('login-username').focus();
});

$('btn-menu-toggle').addEventListener('click', () => {
  $('sidebar').classList.toggle('open');
});

// ── HOME ─────────────────────────────────────────────────────────
async function loadHome() {
  const container = $('home-cards');
  container.innerHTML = '<p class="text-muted">Carregando…</p>';
  try {
    const [livrosData, empData, exData, configData] = await Promise.allSettled([
      Api.livros(null, null, 1, 1),
      isStaff() ? Api.emprestimos(null, 'ABERTO', 1, 1) : Api.meusEmprestimos('ABERTO', 1, 1),
      isStaff() ? Api.exemplares(null, 'DISPONIVEL', 1, 1) : null,
      Api.configuracoes(),
    ]);

    const stats = [];

    if (livrosData.status === 'fulfilled') {
      stats.push({ icon: 'bi-book', label: 'Títulos no catálogo', value: livrosData.value.total, nav: 'catalogo' });
    }
    if (empData.status === 'fulfilled') {
      stats.push({ icon: 'bi-arrow-left-right', label: isReader() ? 'Meus empréstimos abertos' : 'Empréstimos abertos', value: empData.value.total, nav: isReader() ? 'meus-emprestimos' : 'emprestimos' });
    }
    if (exData.status === 'fulfilled' && exData.value) {
      stats.push({ icon: 'bi-bookmark-check', label: 'Exemplares disponíveis', value: exData.value.total, nav: 'exemplares' });
    }
    if (configData.status === 'fulfilled') {
      const cfg = configData.value;
      const limite = prop(cfg, 'limiteExemplares') ?? prop(cfg, 'LimiteExemplares') ?? '—';
      const prazo  = prop(cfg, 'prazoDias') ?? prop(cfg, 'PrazoDias') ?? '—';
      stats.push({ icon: 'bi-person-badge', label: 'Limite por aluno', value: limite, nav: null });
      stats.push({ icon: 'bi-calendar3', label: 'Prazo de empréstimo', value: prazo + ' dias', nav: null });
    }

    container.innerHTML = '';
    stats.forEach(s => {
      const card = el('div', 'home-stat-card');
      card.innerHTML = `
        <i class="bi ${s.icon} stat-icon"></i>
        <span class="stat-label">${s.label}</span>
        <span class="stat-value">${s.value}</span>
      `;
      if (s.nav) card.addEventListener('click', () => navigateTo(s.nav));
      else card.style.cursor = 'default';
      container.appendChild(card);
    });
  } catch {
    container.innerHTML = '<p class="text-muted">Não foi possível carregar o painel.</p>';
  }
}

// ── SELF-CHECKOUT ─────────────────────────────────────────────────
let checkoutItems = [];
let returnItems = [];

function setCheckoutMode(mode) {
  const isLoan = mode === 'loan';
  $('checkout-loan-mode').classList.toggle('hidden', !isLoan);
  $('checkout-return-mode').classList.toggle('hidden', isLoan);
  $('btn-mode-loan').className = `btn ${isLoan ? 'btn-primary' : 'btn-outline'}`;
  $('btn-mode-return').className = `btn ${isLoan ? 'btn-outline' : 'btn-primary'}`;
  $('btn-mode-loan').setAttribute('aria-selected', String(isLoan));
  $('btn-mode-return').setAttribute('aria-selected', String(!isLoan));
  if (isLoan) $('checkout-codigo').focus();
  else $('return-codigo').focus();
}

$('btn-mode-loan').addEventListener('click', () => setCheckoutMode('loan'));
$('btn-mode-return').addEventListener('click', () => setCheckoutMode('return'));

function initSelfCheckout() {
  checkoutItems = [];
  renderCheckoutItems();
  hide('checkout-receipt');
  hide('checkout-error');
  hide('checkout-lookup-result');
  $('checkout-codigo').value = '';
  $('checkout-loan-layout').style.display = '';
  initSelfReturn();
  setCheckoutMode('loan');
}

$('checkout-codigo').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); addCheckoutItem(); }
});
$('btn-checkout-add').addEventListener('click', addCheckoutItem);

async function addCheckoutItem() {
  const codigo = $('checkout-codigo').value.trim();
  if (!codigo) return;
  const result = $('checkout-lookup-result');
  result.className = 'lookup-result';
  result.textContent = 'Consultando…';
  show('checkout-lookup-result');

  try {
    const ex = await Api.exemplarPorCodigo(codigo);
    const tombo = prop(ex, 'codigoTombo') || prop(ex, 'CodigoTombo');
    const titulo = prop(ex, 'titulo') || prop(ex, 'Titulo');
    const situacao = prop(ex, 'situacao') || prop(ex, 'Situacao');
    const idExemplar = prop(ex, 'idExemplar') || prop(ex, 'IdExemplar');

    if (checkoutItems.find(i => i.codigo === tombo)) {
      result.className = 'lookup-result error';
      result.textContent = 'Exemplar já adicionado.';
      return;
    }
    if (situacao !== 'DISPONIVEL') {
      result.className = 'lookup-result error';
      result.innerHTML = `<strong>${titulo}</strong>Situação: ${situacao} — não disponível para empréstimo.`;
      return;
    }
    result.innerHTML = `<strong>${titulo}</strong>Código: ${tombo} — Disponível ✓`;
    checkoutItems.push({ codigo: tombo, titulo, idExemplar });
    renderCheckoutItems();
    $('checkout-codigo').value = '';
    $('checkout-codigo').focus();
  } catch (err) {
    result.className = 'lookup-result error';
    result.textContent = err.message;
  }
}

function renderCheckoutItems() {
  const ul = $('checkout-items');
  const btn = $('btn-checkout-confirm');
  $('checkout-count').textContent = checkoutItems.length;
  if (checkoutItems.length === 0) {
    ul.innerHTML = '<li class="empty-state">Nenhum exemplar adicionado ainda.</li>';
    btn.disabled = true;
    btn.innerHTML = '<i class="bi bi-check-circle"></i> Confirmar empréstimo';
    return;
  }
  btn.disabled = false;
  ul.innerHTML = '';
  checkoutItems.forEach((item, idx) => {
    const li = el('li', 'item-row');
    li.innerHTML = `
      <span class="item-code">${item.codigo}</span>
      <span class="item-title">${item.titulo}</span>
      <button class="btn-remove" title="Remover"><i class="bi bi-x-lg"></i></button>
    `;
    li.querySelector('.btn-remove').addEventListener('click', () => {
      checkoutItems.splice(idx, 1);
      renderCheckoutItems();
    });
    ul.appendChild(li);
  });
}

$('btn-checkout-confirm').addEventListener('click', async () => {
  clearAlert('checkout-error');
  const btn = $('btn-checkout-confirm');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Confirmando…';
  try {
    const codigos = checkoutItems.map(i => i.codigo);
    const data = await Api.selfCheckout(codigos);
    showReceipt(data);
  } catch (err) {
    showErr('checkout-error', err.message);
    btn.disabled = false;
    btn.innerHTML = '<i class="bi bi-check-circle"></i> Confirmar empréstimo';
  }
});

function showReceipt(data) {
  const confirmButton = $('btn-checkout-confirm');
  confirmButton.disabled = true;
  confirmButton.innerHTML = '<i class="bi bi-check-circle"></i> Confirmar empréstimo';
  show('checkout-receipt');
  const prazoStr = prop(data, 'dataHoraPrevista') || prop(data, 'DataHoraPrevista');
  const prazo = new Date(prazoStr);
  $('receipt-prazo').textContent = 'Devolução até: ' + prazo.toLocaleDateString('pt-BR');
  const tbody = $('checkout-receipt').querySelector('tbody');
  tbody.innerHTML = '';
  const itens = prop(data, 'itens') || prop(data, 'Itens') || [];
  itens.forEach(item => {
    const tr = document.createElement('tr');
    const tombo = prop(item, 'codigoTombo') || prop(item, 'CodigoTombo');
    const titulo = prop(item, 'titulo') || prop(item, 'Titulo');
    tr.innerHTML = `<td><code>${tombo}</code></td><td>${titulo}</td>`;
    tbody.appendChild(tr);
  });
  $('checkout-loan-layout').style.display = 'none';
}

$('btn-checkout-novo').addEventListener('click', () => {
  checkoutItems = [];
  renderCheckoutItems();
  hide('checkout-error');
  hide('checkout-lookup-result');
  $('checkout-codigo').value = '';
  $('checkout-loan-layout').style.display = '';
  hide('checkout-receipt');
  $('checkout-codigo').focus();
});

function initSelfReturn() {
  returnItems = [];
  renderReturnItems();
  hide('return-receipt');
  hide('return-error');
  hide('return-lookup-result');
  $('return-codigo').value = '';
  $('checkout-return-layout').style.display = '';
}

$('return-codigo').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); addReturnItem(); }
});
$('btn-return-add').addEventListener('click', addReturnItem);

async function addReturnItem() {
  const codigo = $('return-codigo').value.trim();
  if (!codigo) return;
  const result = $('return-lookup-result');
  result.className = 'lookup-result';
  result.textContent = 'Consultando…';
  show('return-lookup-result');

  try {
    const ex = await Api.exemplarPorCodigo(codigo);
    const tombo = prop(ex, 'codigoTombo') || prop(ex, 'CodigoTombo');
    const titulo = prop(ex, 'titulo') || prop(ex, 'Titulo');
    const situacao = prop(ex, 'situacao') || prop(ex, 'Situacao');
    if (returnItems.find(item => item.codigo === tombo)) {
      result.className = 'lookup-result error';
      result.textContent = 'Exemplar já adicionado.';
      return;
    }
    if (situacao !== 'EMPRESTADO') {
      result.className = 'lookup-result error';
      result.innerHTML = `<strong>${titulo}</strong>Este exemplar não está emprestado.`;
      return;
    }
    result.innerHTML = `<strong>${titulo}</strong>Código: ${tombo} — pronto para devolver ✓`;
    returnItems.push({ codigo: tombo, titulo });
    renderReturnItems();
    $('return-codigo').value = '';
    $('return-codigo').focus();
  } catch (err) {
    result.className = 'lookup-result error';
    result.textContent = err.message;
  }
}

function renderReturnItems() {
  const ul = $('return-items');
  const btn = $('btn-return-confirm');
  $('return-count').textContent = returnItems.length;
  btn.innerHTML = '<i class="bi bi-check-circle"></i> Confirmar devolução';
  if (returnItems.length === 0) {
    ul.innerHTML = '<li class="empty-state">Nenhum exemplar adicionado ainda.</li>';
    btn.disabled = true;
    return;
  }
  btn.disabled = false;
  ul.innerHTML = '';
  returnItems.forEach((item, index) => {
    const li = el('li', 'item-row');
    li.innerHTML = `
      <span class="item-code">${item.codigo}</span>
      <span class="item-title">${item.titulo}</span>
      <button class="btn-remove" title="Remover"><i class="bi bi-x-lg"></i></button>
    `;
    li.querySelector('.btn-remove').addEventListener('click', () => {
      returnItems.splice(index, 1);
      renderReturnItems();
    });
    ul.appendChild(li);
  });
}

$('btn-return-confirm').addEventListener('click', async () => {
  clearAlert('return-error');
  const btn = $('btn-return-confirm');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Confirmando…';
  try {
    const data = await Api.selfReturn(returnItems.map(item => item.codigo));
    showReturnReceipt(data);
  } catch (err) {
    showErr('return-error', err.message);
    btn.disabled = false;
    btn.innerHTML = '<i class="bi bi-check-circle"></i> Confirmar devolução';
  }
});

function showReturnReceipt(data) {
  const btn = $('btn-return-confirm');
  btn.disabled = true;
  btn.innerHTML = '<i class="bi bi-check-circle"></i> Confirmar devolução';
  const tbody = $('return-receipt-table').querySelector('tbody');
  tbody.innerHTML = '';
  const items = prop(data, 'itens') || prop(data, 'Itens') || [];
  items.forEach(item => {
    const codigo = prop(item, 'codigoTombo') || prop(item, 'CodigoTombo');
    const titulo = prop(item, 'titulo') || prop(item, 'Titulo');
    const idEmprestimo = prop(item, 'idEmprestimo') || prop(item, 'IdEmprestimo');
    const tr = document.createElement('tr');
    tr.innerHTML = `<td><code>${codigo}</code></td><td>${titulo}</td><td>#${idEmprestimo}</td>`;
    tbody.appendChild(tr);
  });
  $('checkout-return-layout').style.display = 'none';
  show('return-receipt');
}

$('btn-return-new').addEventListener('click', () => {
  initSelfReturn();
  $('return-codigo').focus();
});

// ── MEUS EMPRÉSTIMOS ─────────────────────────────────────────────
let _meusSituacao = '';
$('filter-meus-situacao').addEventListener('change', (e) => {
  _meusSituacao = e.target.value;
  loadMeusEmprestimos(1);
});

async function loadMeusEmprestimos(page) {
  const container = $('meus-emprestimos-list');
  container.innerHTML = '<p class="text-muted"><span class="spinner"></span> Carregando…</p>';
  try {
    const data = await Api.meusEmprestimos(_meusSituacao || null, page, 10);
    renderLoanList(container, data.items, false);
    renderPagination($('meus-emprestimos-pagination'), data, page, loadMeusEmprestimos);
  } catch (err) {
    container.innerHTML = `<p class="text-muted">${err.message}</p>`;
  }
}

// ── CATÁLOGO ─────────────────────────────────────────────────────
let _catQ = '', _catCategoria = '';
let _catDebounce = null;

async function loadCatalogo(page) {
  if ($('filter-livros-categoria').options.length <= 1) {
    try {
      const cats = await Api.categorias(null, 1, 100);
      cats.items.forEach(c => {
        const nome = prop(c, 'nome') || prop(c, 'Nome');
        const id   = prop(c, 'idCategoria') || prop(c, 'IdCategoria');
        const opt = new Option(nome, id);
        $('filter-livros-categoria').appendChild(opt);
      });
    } catch {}
  }

  const grid = $('livros-grid');
  grid.innerHTML = '<p class="text-muted"><span class="spinner"></span> Carregando…</p>';
  try {
    const data = await Api.livros(_catQ || null, _catCategoria || null, page, 20);
    grid.innerHTML = '';
    if (!data.items.length) {
      grid.innerHTML = '<p class="empty-list">Nenhum livro encontrado.</p>';
    }
    data.items.forEach(livro => {
      const titulo    = prop(livro, 'titulo') || prop(livro, 'Titulo');
      const editora   = prop(livro, 'editora') || prop(livro, 'Editora');
      const ano       = prop(livro, 'anoPublicacao') || prop(livro, 'AnoPublicacao');
      const categoria = prop(livro, 'categoria') || prop(livro, 'Categoria');
      const disp      = prop(livro, 'disponiveis') ?? prop(livro, 'Disponiveis') ?? 0;
      const idLivro   = prop(livro, 'idLivro') || prop(livro, 'IdLivro');
      const card = el('div', 'book-card');
      card.innerHTML = `
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:.5rem">
          <div class="book-title" style="flex:1">${titulo}</div>
          ${isStaff() ? `<button class="btn btn-danger btn-sm btn-del-book-card" data-id="${idLivro}" title="Excluir livro do catálogo" style="padding:.25rem .5rem;font-size:12px;border-radius:6px;line-height:1"><i class="bi bi-trash"></i></button>` : ''}
        </div>
        <div class="book-authors text-sm">${editora} · ${ano}</div>
        <div class="book-meta">
          <span class="pill pill-maint">${categoria}</span>
          <span class="book-avail ${disp === 0 ? 'zero' : ''}">${disp} disponíve${disp === 1 ? 'l' : 'is'}</span>
        </div>
      `;

      card.addEventListener('click', (e) => {
        if (e.target.closest('.btn-del-book-card')) return;
        openLivroModal(idLivro);
      });

      const btnDelBook = card.querySelector('.btn-del-book-card');
      if (btnDelBook) {
        btnDelBook.addEventListener('click', async (e) => {
          e.stopPropagation();
          if (!confirm(`Deseja realmente excluir o livro "${titulo}" do catálogo?`)) return;
          btnDelBook.disabled = true;
          try {
            await Api.excluirLivro(idLivro);
            loadCatalogo(page);
          } catch (err) {
            alert('Não foi possível excluir o livro: ' + err.message);
            btnDelBook.disabled = false;
          }
        });
      }

      grid.appendChild(card);
    });
    renderPagination($('livros-pagination'), data, page, loadCatalogo);
  } catch (err) {
    grid.innerHTML = `<p class="text-muted">${err.message}</p>`;
  }
}

$('filter-livros-q').addEventListener('input', (e) => {
  _catQ = e.target.value.trim();
  clearTimeout(_catDebounce);
  _catDebounce = setTimeout(() => loadCatalogo(1), 400);
});
$('filter-livros-categoria').addEventListener('change', (e) => {
  _catCategoria = e.target.value;
  loadCatalogo(1);
});

$('btn-novo-livro').addEventListener('click', () => openNovoLivroModal());

async function openNovoLivroModal() {
  openModal('Novo Livro', `
    <div class="field">
      <label><i class="bi bi-fonts"></i> Título</label>
      <input id="nl-titulo" type="text" placeholder="Ex: Algoritmos e Estruturas de Dados" />
    </div>
    <div class="field">
      <label><i class="bi bi-upc"></i> ISBN (opcional)</label>
      <input id="nl-isbn" type="text" placeholder="10 ou 13 dígitos (opcional)" />
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:.75rem">
      <div class="field">
        <label><i class="bi bi-building"></i> Editora</label>
        <select id="nl-editora"><option value="">Carregando...</option></select>
      </div>
      <div class="field">
        <label><i class="bi bi-tag"></i> Categoria</label>
        <select id="nl-categoria"><option value="">Carregando...</option></select>
      </div>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:.75rem">
      <div class="field">
        <label><i class="bi bi-calendar3"></i> Ano de Publicação</label>
        <input id="nl-ano" type="number" min="1450" max="2050" value="${new Date().getFullYear()}" />
      </div>
      <div class="field">
        <label><i class="bi bi-123"></i> Edição</label>
        <input id="nl-edicao" type="number" min="1" max="999" value="1" />
      </div>
    </div>
    <div class="field">
      <label><i class="bi bi-person"></i> Autor</label>
      <select id="nl-autor"><option value="">Carregando...</option></select>
    </div>
    <div id="nl-error" class="alert alert-error hidden"></div>
    <button id="btn-nl-confirm" class="btn btn-primary"><i class="bi bi-check-lg"></i> Cadastrar Livro</button>
  `);

  // Carrega editoras, categorias e autores em paralelo
  try {
    const [edRes, catRes, autRes] = await Promise.all([
      Api.editoras(null, 1, 100),
      Api.categorias(null, 1, 100),
      Api.autores(null, 1, 100)
    ]);

    const selEd = $('nl-editora');
    selEd.innerHTML = '<option value="">Selecione a editora...</option>';
    (edRes.items || []).forEach(e => {
      const id = prop(e, 'idEditora') || prop(e, 'IdEditora');
      const nome = prop(e, 'nome') || prop(e, 'Nome');
      selEd.appendChild(new Option(nome, id));
    });

    const selCat = $('nl-categoria');
    selCat.innerHTML = '<option value="">Selecione a categoria...</option>';
    (catRes.items || []).forEach(c => {
      const id = prop(c, 'idCategoria') || prop(c, 'IdCategoria');
      const nome = prop(c, 'nome') || prop(c, 'Nome');
      selCat.appendChild(new Option(nome, id));
    });

    const selAut = $('nl-autor');
    selAut.innerHTML = '<option value="">Selecione o autor principal...</option>';
    (autRes.items || []).forEach(a => {
      const id = prop(a, 'idAutor') || prop(a, 'IdAutor');
      const nome = prop(a, 'nome') || prop(a, 'Nome');
      selAut.appendChild(new Option(nome, id));
    });
  } catch (err) {
    showErr('nl-error', 'Erro ao carregar dados de apoio: ' + err.message);
  }

  $('btn-nl-confirm').addEventListener('click', async () => {
    clearAlert('nl-error');
    const titulo = $('nl-titulo').value.trim();
    const isbn = $('nl-isbn').value.trim() || null;
    const idEditora = parseInt($('nl-editora').value);
    const idCategoria = parseInt($('nl-categoria').value);
    const ano = parseInt($('nl-ano').value);
    const edicao = parseInt($('nl-edicao').value);
    const idAutor = parseInt($('nl-autor').value);

    if (!titulo || !idEditora || !idCategoria || !ano || !edicao || !idAutor) {
      showErr('nl-error', 'Preencha título, editora, categoria, ano, edição e autor.');
      return;
    }

    $('btn-nl-confirm').disabled = true;
    $('btn-nl-confirm').innerHTML = '<span class="spinner"></span> Cadastrando...';

    try {
      await Api.criarLivro({
        titulo: titulo,
        idEditora: idEditora,
        idCategoria: idCategoria,
        anoPublicacao: ano,
        numeroEdicao: edicao,
        idsAutores: [idAutor],
        isbn: isbn
      });
      closeModal();
      loadCatalogo(1);
    } catch (err) {
      showErr('nl-error', err.message);
      $('btn-nl-confirm').disabled = false;
      $('btn-nl-confirm').innerHTML = '<i class="bi bi-check-lg"></i> Cadastrar Livro';
    }
  });
}

async function openLivroModal(id) {
  openModal('Detalhes do Livro', '<p class="text-muted"><span class="spinner"></span> Carregando…</p>');
  try {
    const l = await Api.livro(id);
    const titulo    = prop(l, 'titulo') || prop(l, 'Titulo');
    const isbn      = prop(l, 'isbn') || prop(l, 'Isbn');
    const edicao    = prop(l, 'numeroEdicao') || prop(l, 'NumeroEdicao');
    const ano       = prop(l, 'anoPublicacao') || prop(l, 'AnoPublicacao');
    const editora   = prop(l, 'editora') || prop(l, 'Editora');
    const categoria = prop(l, 'categoria') || prop(l, 'Categoria');
    const autoresArr = prop(l, 'autores') || prop(l, 'Autores') || [];
    const autores = autoresArr
      .map(a => prop(a, 'nome') || prop(a, 'Nome'))
      .filter(Boolean)
      .join(', ') || '—';
    const exemplArr  = prop(l, 'exemplares') || prop(l, 'Exemplares') || [];
    const exRows = exemplArr.map(x => {
      const ct = prop(x, 'codigoTombo') || prop(x, 'CodigoTombo');
      const sit = prop(x, 'situacao') || prop(x, 'Situacao');
      const da  = prop(x, 'dataAquisicao') || prop(x, 'DataAquisicao');
      const idX = prop(x, 'idExemplar') || prop(x, 'IdExemplar');
      return `<tr>
        <td><code>${ct}</code></td>
        <td>${situacaoPill(sit)}</td>
        <td>${fmtDate(da)}</td>
        ${isStaff() && sit !== 'EMPRESTADO' ? `<td style="text-align:right"><button class="btn btn-danger btn-sm btn-del-ex-inline" data-id="${idX}" data-codigo="${ct}" title="Excluir exemplar"><i class="bi bi-trash"></i></button></td>` : '<td></td>'}
      </tr>`;
    }).join('') || '<tr><td colspan="4" class="text-muted">Sem exemplares.</td></tr>';

    $('modal-body').innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:1rem">
        <div>
          <p class="text-muted text-sm" style="text-transform:uppercase;letter-spacing:.05em">ISBN ${isbn || '—'} · Ed. ${edicao} · ${ano}</p>
          <h2 style="font-size:1.1rem;margin:.35rem 0">${titulo}</h2>
          <p><strong>Autores:</strong> ${autores}</p>
          <p><strong>Editora:</strong> ${editora} &nbsp;·&nbsp; <strong>Categoria:</strong> ${categoria}</p>
        </div>
        ${isStaff() ? `<button id="btn-modal-del-livro" class="btn btn-danger btn-sm" style="flex-shrink:0"><i class="bi bi-trash"></i> Excluir livro</button>` : ''}
      </div>
      <div style="margin-top:1rem">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:.5rem">
          <h4 style="margin:0"><i class="bi bi-bookmark"></i> Exemplares</h4>
          ${isStaff() ? `<button id="btn-modal-add-ex" class="btn btn-primary btn-sm"><i class="bi bi-plus-lg"></i> Adicionar exemplar</button>` : ''}
        </div>
        <div class="table-wrap">
          <table class="table">
            <thead><tr><th>Código</th><th>Situação</th><th>Aquisição</th><th style="width:50px"></th></tr></thead>
            <tbody>${exRows}</tbody>
          </table>
        </div>
      </div>
    `;

    const btnAddEx = $('btn-modal-add-ex');
    if (btnAddEx) {
      btnAddEx.addEventListener('click', () => {
        openNovoExemplarModal(id);
      });
    }

    const btnDelLivro = $('btn-modal-del-livro');
    if (btnDelLivro) {
      btnDelLivro.addEventListener('click', async () => {
        if (!confirm(`Deseja realmente excluir o livro "${titulo}" e seus exemplares?`)) return;
        btnDelLivro.disabled = true;
        try {
          await Api.excluirLivro(id);
          closeModal();
          loadCatalogo(1);
        } catch (err) {
          alert('Não foi possível excluir o livro: ' + err.message);
          btnDelLivro.disabled = false;
        }
      });
    }

    // Handlers para exclusão de exemplar dentro do modal
    $('modal-body').querySelectorAll('.btn-del-ex-inline').forEach(btn => {
      btn.addEventListener('click', async () => {
        const idEx = btn.dataset.id;
        const cod = btn.dataset.codigo;
        if (!confirm(`Deseja realmente excluir o exemplar ${cod}?`)) return;
        btn.disabled = true;
        try {
          await Api.excluirExemplar(idEx);
          openLivroModal(id); // Recarrega o modal do livro
          if (State.section === 'catalogo') loadCatalogo(1);
        } catch (err) {
          alert('Não foi possível excluir o exemplar: ' + err.message);
          btn.disabled = false;
        }
      });
    });
  } catch (err) {
    $('modal-body').innerHTML = `<p class="alert alert-error">${err.message}</p>`;
  }
}

// ── EMPRÉSTIMOS (staff) ───────────────────────────────────────────
let _empSituacao = '';
$('filter-emp-situacao').addEventListener('change', (e) => {
  _empSituacao = e.target.value;
  loadEmprestimos(1);
});

async function loadEmprestimos(page) {
  const container = $('emprestimos-list');
  container.innerHTML = '<p class="text-muted"><span class="spinner"></span> Carregando…</p>';
  try {
    const data = await Api.emprestimos(null, _empSituacao || null, page, 15);
    renderLoanList(container, data.items, true);
    renderPagination($('emprestimos-pagination'), data, page, loadEmprestimos);
  } catch (err) {
    container.innerHTML = `<p class="text-muted">${err.message}</p>`;
  }
}

$('btn-novo-emprestimo').addEventListener('click', openNovoEmprestimoModal);

function openNovoEmprestimoModal() {
  openModal('Novo Empréstimo (Balcão)', `
    <div class="field">
      <label><i class="bi bi-person"></i> ID do Usuário</label>
      <input id="ne-usuario" type="number" min="1" placeholder="ID do leitor" />
    </div>
    <div class="field">
      <label><i class="bi bi-upc-scan"></i> Códigos de Tombo</label>
      <textarea id="ne-codigos" rows="3" placeholder="Um código por linha"></textarea>
    </div>
    <div id="ne-error" class="alert alert-error hidden"></div>
    <button id="btn-ne-confirm" class="btn btn-primary"><i class="bi bi-check-lg"></i> Registrar empréstimo</button>
  `);
  $('btn-ne-confirm').addEventListener('click', async () => {
    clearAlert('ne-error');
    const idUsuario = parseInt($('ne-usuario').value);
    const codigos = $('ne-codigos').value.split('\n').map(s => s.trim()).filter(Boolean);
    if (!idUsuario || codigos.length === 0) {
      showErr('ne-error', 'Informe o ID do usuário e pelo menos um código.');
      return;
    }
    $('btn-ne-confirm').disabled = true;
    try {
      await Api.criarEmprestimoBalcao(idUsuario, codigos);
      closeModal();
      loadEmprestimos(1);
    } catch (err) {
      showErr('ne-error', err.message);
      $('btn-ne-confirm').disabled = false;
    }
  });
}

function renderLoanList(container, items, showUser) {
  container.innerHTML = '';
  if (!items || items.length === 0) {
    container.innerHTML = '<p class="empty-list">Nenhum empréstimo encontrado.</p>';
    return;
  }
  items.forEach(emp => {
    const idEmp    = prop(emp, 'idEmprestimo') || prop(emp, 'IdEmprestimo');
    const canal    = prop(emp, 'canal') || prop(emp, 'Canal');
    const nomeUsr  = prop(emp, 'nomeUsuario') || prop(emp, 'NomeUsuario') || prop(emp, 'idUsuario') || prop(emp, 'IdUsuario');
    const prazo    = prop(emp, 'dataHoraPrevista') || prop(emp, 'DataHoraPrevista');
    const pendente = prop(emp, 'itensPendentes') ?? prop(emp, 'ItensPendentes') ?? '?';
    const total    = prop(emp, 'quantidadeItens') ?? prop(emp, 'QuantidadeItens') ?? '?';
    const situacao = prop(emp, 'situacao') || prop(emp, 'Situacao');
    const atrasado = prop(emp, 'atrasado') ?? prop(emp, 'Atrasado') ?? false;

    const card = el('div', 'loan-card' + (atrasado ? ' atrasado' : ''));
    card.innerHTML = `
      <div class="loan-info">
        <div class="loan-id">#${idEmp} · ${canal === 'SELF_CHECKOUT' ? 'Self-Checkout' : 'Balcão'}</div>
        ${showUser ? `<div class="loan-user">${nomeUsr}</div>` : ''}
        <div class="loan-meta">
          <span><i class="bi bi-calendar3"></i> Prazo: ${fmtDate(prazo)}</span>
          <span><i class="bi bi-collection"></i> ${pendente}/${total} pendentes</span>
        </div>
      </div>
      <div class="loan-badges">
        ${situacaoPill(situacao)}
        ${atrasado ? '<span class="pill pill-late"><i class="bi bi-exclamation-triangle"></i> Atrasado</span>' : ''}
      </div>
      <div class="loan-actions">
        <button class="btn btn-outline btn-sm btn-detail" data-id="${idEmp}"><i class="bi bi-eye"></i> Ver</button>
        ${isStaff() && situacao === 'ABERTO' ? `<button class="btn btn-primary btn-sm btn-devolver" data-id="${idEmp}"><i class="bi bi-arrow-return-left"></i> Devolver</button>` : ''}
      </div>
    `;
    card.querySelector('.btn-detail').addEventListener('click', () => openEmprestimoModal(idEmp));
    const btnDev = card.querySelector('.btn-devolver');
    if (btnDev) btnDev.addEventListener('click', () => openDevolucaoModal(idEmp));
    container.appendChild(card);
  });
}

async function openEmprestimoModal(id) {
  openModal('Comprovante #' + id, '<p class="text-muted"><span class="spinner"></span> Carregando…</p>');
  try {
    const emp = await Api.emprestimo(id);
    const nomeUsr = prop(emp, 'nomeUsuario') || prop(emp, 'NomeUsuario');
    const canal   = prop(emp, 'canal') || prop(emp, 'Canal');
    const situacao = prop(emp, 'situacao') || prop(emp, 'Situacao');
    const prazo   = prop(emp, 'dataHoraPrevista') || prop(emp, 'DataHoraPrevista');
    const itens   = prop(emp, 'itens') || prop(emp, 'Itens') || [];

    const rows = itens.map(i => {
      const tombo = prop(i, 'codigoTombo') || prop(i, 'CodigoTombo');
      const titulo = prop(i, 'titulo') || prop(i, 'Titulo');
      const dev = prop(i, 'dataHoraDevolucao') || prop(i, 'DataHoraDevolucao');
      return `<tr>
        <td><code>${tombo}</code></td>
        <td>${titulo}</td>
        <td>${dev ? fmtDatetime(dev) : '<span class="pill pill-borrowed">Pendente</span>'}</td>
      </tr>`;
    }).join('');

    $('modal-body').innerHTML = `
      <div>
        <p><strong>Usuário:</strong> ${nomeUsr}</p>
        <p><strong>Canal:</strong> ${canal === 'SELF_CHECKOUT' ? 'Self-Checkout' : 'Balcão'}</p>
        <p><strong>Situação:</strong> ${situacaoPill(situacao)}</p>
        <p><strong>Prazo:</strong> ${fmtDate(prazo)}</p>
      </div>
      <div class="table-wrap">
        <table class="table">
          <thead><tr><th>Código</th><th>Título</th><th>Devolução</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
    `;
  } catch (err) {
    $('modal-body').innerHTML = `<p class="alert alert-error">${err.message}</p>`;
  }
}

function openDevolucaoModal(idEmprestimo) {
  openModal('Registrar Devolução', `
    <p class="text-muted">Informe os IDs dos exemplares a devolver (separados por vírgula ou linha).</p>
    <div class="field">
      <label><i class="bi bi-collection"></i> IDs dos Exemplares</label>
      <textarea id="dev-ids" rows="3" placeholder="Ex: 1, 2, 3"></textarea>
    </div>
    <div id="dev-error" class="alert alert-error hidden"></div>
    <button id="btn-dev-confirm" class="btn btn-primary"><i class="bi bi-check-lg"></i> Confirmar devolução</button>
  `);
  $('btn-dev-confirm').addEventListener('click', async () => {
    clearAlert('dev-error');
    const raw = $('dev-ids').value;
    const ids = raw.split(/[\n,]+/).map(s => parseInt(s.trim())).filter(n => n > 0);
    if (ids.length === 0) { showErr('dev-error', 'Informe pelo menos um ID.'); return; }
    $('btn-dev-confirm').disabled = true;
    try {
      await Api.registrarDevolucao(idEmprestimo, ids);
      closeModal();
      if (State.section === 'emprestimos') loadEmprestimos(1);
    } catch (err) {
      showErr('dev-error', err.message);
      $('btn-dev-confirm').disabled = false;
    }
  });
}

// ── EXEMPLARES ───────────────────────────────────────────────────
let _exSituacao = '';
$('filter-ex-situacao').addEventListener('change', (e) => {
  _exSituacao = e.target.value;
  loadExemplares(1);
});

async function loadExemplares(page) {
  const tbody = $('exemplares-tbody');
  tbody.innerHTML = '<tr class="loading-row"><td colspan="5"><span class="spinner"></span> Carregando…</td></tr>';
  try {
    const data = await Api.exemplares(null, _exSituacao || null, page, 20);
    tbody.innerHTML = '';
    if (!data.items.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted" style="padding:1.5rem">Nenhum exemplar.</td></tr>';
    }
    data.items.forEach(x => {
      const tombo    = prop(x, 'codigoTombo') || prop(x, 'CodigoTombo');
      const titulo   = prop(x, 'titulo') || prop(x, 'Titulo');
      const situacao = prop(x, 'situacao') || prop(x, 'Situacao');
      const dataAq   = prop(x, 'dataAquisicao') || prop(x, 'DataAquisicao');
      const idEx     = prop(x, 'idExemplar') || prop(x, 'IdExemplar');

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><code>${tombo}</code></td>
        <td>${titulo}</td>
        <td>${situacaoPill(situacao)}</td>
        <td>${fmtDate(dataAq)}</td>
        <td>
          <div style="display:flex;gap:.35rem;flex-wrap:wrap">
            ${situacao !== 'EMPRESTADO' ? `<button class="btn btn-outline btn-sm btn-sit" data-id="${idEx}"><i class="bi bi-pencil"></i> Alterar</button>` : ''}
            ${isStaff() && situacao !== 'EMPRESTADO' ? `<button class="btn btn-danger btn-sm btn-del-ex" data-id="${idEx}" data-codigo="${tombo}"><i class="bi bi-trash"></i> Excluir</button>` : ''}
          </div>
        </td>
      `;
      const btnSit = tr.querySelector('.btn-sit');
      if (btnSit) btnSit.addEventListener('click', () => openAlterarSituacaoModal(idEx, tombo));

      const btnDel = tr.querySelector('.btn-del-ex');
      if (btnDel) {
        btnDel.addEventListener('click', async () => {
          if (!confirm(`Deseja realmente excluir o exemplar ${tombo}?`)) return;
          btnDel.disabled = true;
          try {
            await Api.excluirExemplar(idEx);
            loadExemplares(page);
          } catch (err) {
            alert('Não foi possível excluir o exemplar: ' + err.message);
            btnDel.disabled = false;
          }
        });
      }
      tbody.appendChild(tr);
    });
    renderPagination($('exemplares-pagination'), data, page, loadExemplares);
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5" class="text-muted">${err.message}</td></tr>`;
  }
}

function openAlterarSituacaoModal(id, codigo) {
  openModal('Alterar Situação — ' + codigo, `
    <div class="field">
      <label><i class="bi bi-arrow-repeat"></i> Nova situação</label>
      <select id="sit-nova">
        <option value="DISPONIVEL">Disponível</option>
        <option value="MANUTENCAO">Manutenção</option>
        <option value="INATIVO">Inativo</option>
      </select>
    </div>
    <div id="sit-error" class="alert alert-error hidden"></div>
    <button id="btn-sit-confirm" class="btn btn-primary"><i class="bi bi-check-lg"></i> Salvar</button>
  `);
  $('btn-sit-confirm').addEventListener('click', async () => {
    clearAlert('sit-error');
    $('btn-sit-confirm').disabled = true;
    try {
      await Api.alterarSituacaoExemplar(id, $('sit-nova').value);
      closeModal();
      loadExemplares(1);
    } catch (err) {
      showErr('sit-error', err.message);
      $('btn-sit-confirm').disabled = false;
    }
  });
}

$('btn-novo-exemplar').addEventListener('click', () => openNovoExemplarModal());

async function openNovoExemplarModal(presetIdLivro = null) {
  openModal('Novo Exemplar', `
    <div class="field">
      <label><i class="bi bi-book"></i> Livro</label>
      <select id="nex-livro">
        <option value="">Carregando livros...</option>
      </select>
    </div>
    <div class="field">
      <label><i class="bi bi-upc-scan"></i> Código de Tombo</label>
      <input id="nex-codigo" type="text" placeholder="Ex: DEMO-BD-003 ou BIB-00010" />
    </div>
    <div class="field">
      <label><i class="bi bi-calendar3"></i> Data de Aquisição</label>
      <input id="nex-data" type="date" />
    </div>
    <div id="nex-error" class="alert alert-error hidden"></div>
    <button id="btn-nex-confirm" class="btn btn-primary"><i class="bi bi-plus-lg"></i> Criar exemplar</button>
  `);

  const hoje = new Date().toISOString().slice(0, 10);
  $('nex-data').value = hoje;

  // Carrega os livros no select
  try {
    const livrosRes = await Api.livros(null, null, 1, 100);
    const select = $('nex-livro');
    select.innerHTML = '<option value="">Selecione um livro...</option>';
    (livrosRes.items || []).forEach(l => {
      const id = prop(l, 'idLivro') || prop(l, 'IdLivro');
      const tit = prop(l, 'titulo') || prop(l, 'Titulo');
      const opt = document.createElement('option');
      opt.value = id;
      opt.textContent = `#${id} - ${tit}`;
      if (presetIdLivro && id == presetIdLivro) opt.selected = true;
      select.appendChild(opt);
    });
  } catch (err) {
    $('nex-livro').innerHTML = '<option value="">Erro ao carregar livros</option>';
  }

  $('btn-nex-confirm').addEventListener('click', async () => {
    clearAlert('nex-error');
    const idLivro = parseInt($('nex-livro').value);
    const codigo = $('nex-codigo').value.trim();
    const data = $('nex-data').value;

    if (!idLivro || !codigo || !data) {
      showErr('nex-error', 'Preencha todos os campos obrigatórios.');
      return;
    }

    $('btn-nex-confirm').disabled = true;
    $('btn-nex-confirm').innerHTML = '<span class="spinner"></span> Criando...';

    try {
      await Api.criarExemplar({
        idLivro: idLivro,
        codigoTombo: codigo,
        dataAquisicao: data + 'T00:00:00Z'
      });
      closeModal();
      if (State.section === 'exemplares') loadExemplares(1);
      else if (State.section === 'catalogo') loadCatalogo(1);
    } catch (err) {
      showErr('nex-error', err.message);
      $('btn-nex-confirm').disabled = false;
      $('btn-nex-confirm').innerHTML = '<i class="bi bi-plus-lg"></i> Criar exemplar';
    }
  });
}

// ── USUÁRIOS ─────────────────────────────────────────────────────
async function loadUsuarios(page) {
  const tbody = $('usuarios-tbody');
  tbody.innerHTML = '<tr class="loading-row"><td colspan="5"><span class="spinner"></span> Carregando…</td></tr>';
  try {
    const data = await Api.usuarios(page, 20);
    tbody.innerHTML = '';
    if (!data.items.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-muted" style="padding:1.5rem">Nenhum usuário.</td></tr>';
    }
    data.items.forEach(u => {
      const nome     = prop(u, 'nome') || prop(u, 'Nome');
      const username = prop(u, 'username') || prop(u, 'Username');
      const perfil   = prop(u, 'perfil') || prop(u, 'Perfil');
      const ativo    = prop(u, 'ativo') ?? prop(u, 'Ativo');
      const idUsr    = prop(u, 'idUsuario') || prop(u, 'IdUsuario');

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${nome}</td>
        <td><code>${username}</code></td>
        <td>${perfilLabel(perfil)}</td>
        <td>${ativo ? '<span class="pill pill-avail">Ativo</span>' : '<span class="pill pill-inactive">Inativo</span>'}</td>
        <td>
          <div style="display:flex;gap:.5rem;flex-wrap:wrap">
            ${isAdmin() ? `<button class="btn btn-outline btn-sm btn-toggle-user" data-id="${idUsr}" data-ativo="${ativo}">${ativo ? '<i class="bi bi-person-dash"></i> Desativar' : '<i class="bi bi-person-check"></i> Ativar'}</button>` : ''}
            ${isAdmin() && perfil === 'LEITOR' ? `<button class="btn btn-danger btn-sm btn-delete-student" data-id="${idUsr}"><i class="bi bi-trash"></i> Excluir</button>` : ''}
          </div>
        </td>
      `;
      const btn = tr.querySelector('.btn-toggle-user');
      if (btn) {
        btn.addEventListener('click', async () => {
          const novoAtivo = btn.dataset.ativo !== 'true';
          btn.disabled = true;
          try {
            await Api.ativarUsuario(parseInt(btn.dataset.id), novoAtivo);
            loadUsuarios(page);
          } catch (err) {
            alert(err.message);
            btn.disabled = false;
          }
        });
      }
      const btnDelete = tr.querySelector('.btn-delete-student');
      if (btnDelete) {
        btnDelete.addEventListener('click', async () => {
          if (!confirm(`Excluir permanentemente o aluno "${nome}"?\n\nAlunos com histórico de empréstimos não podem ser excluídos.`)) return;
          btnDelete.disabled = true;
          try {
            await Api.excluirAluno(parseInt(btnDelete.dataset.id));
            loadUsuarios(page);
          } catch (err) {
            alert(err.message);
            btnDelete.disabled = false;
          }
        });
      }
      tbody.appendChild(tr);
    });
    renderPagination($('usuarios-pagination'), data, page, loadUsuarios);
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5" class="text-muted">${err.message}</td></tr>`;
  }
}

$('btn-novo-usuario').addEventListener('click', () => {
  const perfilOptions = isAdmin()
    ? `<option value="LEITOR">Aluno</option><option value="BIBLIOTECARIO">Bibliotecário</option><option value="ADMINISTRADOR">Administrador</option>`
    : `<option value="LEITOR">Aluno</option>`;
  openModal('Novo Usuário', `
    <div class="field"><label><i class="bi bi-person"></i> Nome</label><input id="nu-nome" type="text" /></div>
    <div class="field"><label><i class="bi bi-at"></i> Username</label><input id="nu-username" type="text" /></div>
    <div class="field"><label><i class="bi bi-envelope"></i> E-mail</label><input id="nu-email" type="email" /></div>
    <div class="field"><label><i class="bi bi-card-text"></i> CPF (opcional)</label><input id="nu-cpf" type="text" /></div>
    <div class="field"><label><i class="bi bi-lock"></i> Senha</label><input id="nu-senha" type="password" /></div>
    <div class="field"><label><i class="bi bi-shield"></i> Perfil</label><select id="nu-perfil">${perfilOptions}</select></div>
    <div id="nu-error" class="alert alert-error hidden"></div>
    <button id="btn-nu-confirm" class="btn btn-primary"><i class="bi bi-person-plus"></i> Criar usuário</button>
  `);
  $('btn-nu-confirm').addEventListener('click', async () => {
    clearAlert('nu-error');
    $('btn-nu-confirm').disabled = true;
    const body = {
      nome: $('nu-nome').value.trim(),
      username: $('nu-username').value.trim(),
      email: $('nu-email').value.trim(),
      cpf: $('nu-cpf').value.trim() || null,
      senha: $('nu-senha').value,
      perfil: $('nu-perfil').value,
    };
    try {
      await Api.criarUsuario(body);
      closeModal();
      loadUsuarios(1);
    } catch (err) {
      showErr('nu-error', err.message);
      $('btn-nu-confirm').disabled = false;
    }
  });
});

// ── CONFIGURAÇÕES ────────────────────────────────────────────────
async function loadConfiguracoes() {
  clearAlert('config-alert');
  try {
    const cfg = await Api.configuracoes();
    $('cfg-limite').value        = prop(cfg, 'limiteExemplares') ?? prop(cfg, 'LimiteExemplares');
    $('cfg-prazo').value         = prop(cfg, 'prazoDias') ?? prop(cfg, 'PrazoDias');
    $('cfg-bloquear').checked    = prop(cfg, 'bloquearAtrasados') ?? prop(cfg, 'BloquearAtrasados');
    $('cfg-self-checkout').checked = prop(cfg, 'selfCheckoutHabilitado') ?? prop(cfg, 'SelfCheckoutHabilitado');
  } catch (err) {
    showErr('config-alert', 'Erro ao carregar configurações: ' + err.message);
  }
}

$('form-config').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearAlert('config-alert');
  const body = {
    limiteExemplares: parseInt($('cfg-limite').value),
    prazoDias: parseInt($('cfg-prazo').value),
    bloquearAtrasados: $('cfg-bloquear').checked,
    selfCheckoutHabilitado: $('cfg-self-checkout').checked,
  };
  try {
    await Api.atualizarConfiguracoes(body);
    showOk('config-alert', 'Configurações salvas com sucesso.');
  } catch (err) {
    showErr('config-alert', err.message);
  }
});

// ── AUDITORIA ────────────────────────────────────────────────────
async function loadAuditoria(page) {
  const tbody = $('auditoria-tbody');
  tbody.innerHTML = '<tr class="loading-row"><td colspan="4"><span class="spinner"></span> Carregando…</td></tr>';
  try {
    const data = await Api.auditoria(page, 30);
    tbody.innerHTML = '';
    if (!data.items.length) {
      tbody.innerHTML = '<tr><td colspan="4" class="text-muted" style="padding:1.5rem">Sem registros.</td></tr>';
    }
    data.items.forEach(log => {
      const dataEvento = prop(log, 'dataHoraEvento') || prop(log, 'DataHoraEvento');
      const idUsr      = prop(log, 'idUsuario') || prop(log, 'IdUsuario');
      const evento     = prop(log, 'evento') || prop(log, 'Evento');
      const detalhes   = prop(log, 'detalhes') || prop(log, 'Detalhes') || '';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${fmtDatetime(dataEvento)}</td>
        <td>${idUsr}</td>
        <td><code>${evento}</code></td>
        <td class="text-sm text-muted">${detalhes}</td>
      `;
      tbody.appendChild(tr);
    });
    renderPagination($('auditoria-pagination'), data, page, loadAuditoria);
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="4" class="text-muted">${err.message}</td></tr>`;
  }
}

// ── PAGINAÇÃO ────────────────────────────────────────────────────
function renderPagination(container, data, currentPage, loader) {
  container.innerHTML = '';
  const totalPages = Math.ceil(data.total / data.pageSize);
  if (totalPages <= 1) return;

  const info = el('span', 'text-muted', `Página ${currentPage} de ${totalPages}`);
  container.appendChild(info);

  const btnPrev = el('button', 'btn btn-outline btn-sm');
  btnPrev.innerHTML = '<i class="bi bi-chevron-left"></i> Anterior';
  btnPrev.disabled = currentPage <= 1;
  btnPrev.addEventListener('click', () => loader(currentPage - 1));
  container.appendChild(btnPrev);

  const btnNext = el('button', 'btn btn-outline btn-sm');
  btnNext.innerHTML = 'Próxima <i class="bi bi-chevron-right"></i>';
  btnNext.disabled = currentPage >= totalPages;
  btnNext.addEventListener('click', () => loader(currentPage + 1));
  container.appendChild(btnNext);
}

// ── MODAL ────────────────────────────────────────────────────────
function openModal(title, bodyHTML) {
  $('modal-title').textContent = title;
  $('modal-body').innerHTML = bodyHTML;
  $('modal-overlay').classList.remove('hidden');
}
function closeModal() {
  $('modal-overlay').classList.add('hidden');
  $('modal-body').innerHTML = '';
}
$('modal-close').addEventListener('click', closeModal);
$('modal-overlay').addEventListener('click', (e) => {
  if (e.target === $('modal-overlay')) closeModal();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeModal();
});

// ── Fechar sidebar ao clicar fora (mobile) ────────────────────────
document.addEventListener('click', (e) => {
  const sidebar = $('sidebar');
  if (sidebar.classList.contains('open') &&
      !sidebar.contains(e.target) &&
      e.target !== $('btn-menu-toggle')) {
    sidebar.classList.remove('open');
  }
});
