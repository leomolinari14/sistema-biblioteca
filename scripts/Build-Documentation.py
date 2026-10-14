"""Gera o PDF técnico v0.2. Requer Python 3 e reportlab; não é dependência da API."""
from pathlib import Path
from xml.sax.saxutils import escape
import os

from reportlab.pdfgen.canvas import Canvas
from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs' / 'arquitetura-v0.2.pdf'
W, H = A4
L, R = 44, W - 44
WIDTH = R - L
NAVY = HexColor('#17324D')
TEAL = HexColor('#087F8C')
TEXT = HexColor('#283D4B')
MUTED = HexColor('#536D7C')
PALE = HexColor('#EFF6F8')
LINE = HexColor('#D5E2E8')
FUTURE = HexColor('#F4F5F7')

fonts = Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Fonts'
REG, BOLD = 'Helvetica', 'Helvetica-Bold'
if (fonts / 'arial.ttf').exists():
    pdfmetrics.registerFont(TTFont('Body', str(fonts / 'arial.ttf')))
    pdfmetrics.registerFont(TTFont('BodyBold', str(fonts / 'arialbd.ttf')))
    pdfmetrics.registerFontFamily('Body', normal='Body', bold='BodyBold')
    REG, BOLD = 'Body', 'BodyBold'

c = Canvas(str(OUTPUT), pagesize=A4)
c.setTitle('Biblioteca | API, banco e self-checkout | Arquitetura v0.2')
c.setAuthor('Projeto acadêmico de biblioteca')
c.setSubject('Implementação C# / ASP.NET Core e SQL Server, validada em 01/10/2026')


def text(value, x, top, size=10, bold=False, color=TEXT):
    c.setFillColor(color)
    c.setFont(BOLD if bold else REG, size)
    c.drawString(x, H - top - size, value)


def para(value, x, top, width, size=10.3, color=TEXT, max_height=None):
    style = ParagraphStyle('p', fontName=REG, fontSize=size, leading=size * 1.42,
                           textColor=color, spaceAfter=0)
    p = Paragraph(value, style)
    _, height = p.wrap(width, H)
    if max_height is not None and height > max_height:
        raise ValueError(f'Texto excedeu o espaço: {value[:70]} ({height} > {max_height})')
    if top + height > H - 56:
        raise ValueError(f'Texto ultrapassa o rodapé: {value[:70]}')
    p.drawOn(c, x, H - top - height)
    return top + height


def panel(x, top, width, height, fill=PALE, border=LINE):
    c.setFillColor(fill)
    c.setStrokeColor(border)
    c.setLineWidth(.7)
    c.roundRect(x, H - top - height, width, height, 8, fill=1, stroke=1)


def node(title, body, x, top, width, height, future=False):
    panel(x, top, width, height, FUTURE if future else PALE)
    text(title, x+13, top+10, 10.5, True, NAVY)
    para(body, x+13, top+29, width-26, 9.4, MUTED, height-35)


def arrow(x1, y1, x2, y2, color=TEAL):
    c.setStrokeColor(color)
    c.setFillColor(color)
    c.setLineWidth(1.2)
    c.line(x1, H-y1, x2, H-y2)
    import math
    angle = math.atan2(y2-y1, x2-x1)
    p = c.beginPath()
    p.moveTo(x2, H-y2)
    for offset in (-.55, .55):
        p.lineTo(x2 - 6 * math.cos(angle+offset), H-y2 + 6 * math.sin(angle+offset))
    p.close()
    c.drawPath(p, stroke=0, fill=1)


def header(number, title, subtitle):
    c.setFillColor(NAVY)
    c.rect(0, H-10, W, 10, fill=1, stroke=0)
    text('BIBLIOTECA / DOCUMENTAÇÃO TÉCNICA', L, 30, 8.5, True, TEAL)
    text(title, L, 54, 23, True, NAVY)
    para(subtitle, L, 91, WIDTH, 10.2, MUTED)
    c.setStrokeColor(LINE)
    c.line(L, 49, R, 49)
    text('v0.2 | 01/10/2026 | API + SQL Server', L, H-36, 8, color=MUTED)
    text(f'{number:02d} / 06', R-38, H-36, 8, color=MUTED)


def section(title, body, top):
    text(title, L, top, 13, True, NAVY)
    return para(body, L, top+24, WIDTH, 10.4) + 20


def table(rows, top, left_width=152, size=9.5):
    for i, (a, b) in enumerate(rows):
        available = WIDTH - left_width - 24
        style = ParagraphStyle('cell', fontName=REG, fontSize=size, leading=size*1.4)
        p1 = Paragraph(a, style)
        p2 = Paragraph(b, style)
        h1 = p1.wrap(left_width-20, H)[1]
        h2 = p2.wrap(available, H)[1]
        height = max(h1, h2) + 18
        if top+height > H-62:
            raise ValueError('Tabela excedeu a página')
        c.setFillColor(PALE if i % 2 == 0 else white)
        c.rect(L, H-top-height, WIDTH, height, fill=1, stroke=0)
        para(a, L+10, top+9, left_width-20, size, NAVY)
        para(b, L+left_width+10, top+9, available, size)
        top += height
    return top


header(1, 'Biblioteca com self-checkout', 'Arquitetura implementada, regras e guia de validação do primeiro backend.')
panel(L, 143, WIDTH, 105, NAVY, NAVY)
text('UMA API. UM ACERVO. DOIS CANAIS.', L+20, 161, 12, True, white)
para('Empréstimos no balcão e autoempréstimo pelo leitor usam o mesmo banco, '
     'as mesmas regras e a mesma proteção transacional.', L+20, 188, WIDTH-40, 12, white)

y = section('01  O que esta entrega contém',
    'API em <b>C# / ASP.NET Core 10</b>, persistência real em <b>SQL Server</b>, '
    'catálogo, usuários e perfis, empréstimos, autoempréstimo, devoluções parciais, '
    'configurações e auditoria. O modelo acompanha os conceitos das fotos da aula: '
    'PK/FK, relação N:N, transações, procedures e log com NEWID().', 277)
y = section('02  O significado de self-checkout',
    'O leitor entra com a própria conta e confirma a retirada dos exemplares por seus '
    'códigos de tombo. A operação devolve um comprovante com itens e prazo. '
    'Não é uma compra e não envolve pagamento. A devolução permanece com a equipe.', y)
y = section('03  O que ainda não foi desenvolvido',
    'A interface para celular e desktop será decidida na próxima etapa. Não há telas, '
    'leitura por câmera, etiquetas impressas, RFID, aplicativo instalável ou publicação '
    'na internet nesta versão. Os dois tipos de cliente poderão consumir esta API.', y)
panel(L, y+3, WIDTH, 81)
text('VALIDADO EM SQL SERVER REAL', L+16, y+15, 10, True, TEAL)
para('<b>18 testes HTTP passaram</b> e <b>5 invariantes de integridade</b> foram conferidas. '
     'A compilação Release terminou sem erros ou avisos.', L+16, y+36, WIDTH-32, 10)
c.showPage()

header(2, 'Diagrama de arquitetura', 'Monólito modular: um processo de API, com responsabilidades separadas por módulo.')
node('CLIENTE MOBILE', 'Interface futura<br/>Sessão própria do leitor', L, 142, 242, 71, True)
node('CLIENTE DESKTOP', 'Interface futura<br/>Leitor ou equipe', R-242, 142, 242, 71, True)
arrow(L+121, 213, L+121, 258)
arrow(R-121, 213, R-121, 258)
text('HTTPS / JSON + Bearer JWT', L+170, 227, 9, color=TEAL)
node('API ASP.NET CORE  /api/v1', 'Autenticação, perfis, validação, respostas JSON e tratamento de erros', L, 258, WIDTH, 64)
arrow(L+121, 322, L+121, 354)
arrow(R-121, 322, R-121, 354)
node('CATÁLOGO E USUÁRIOS', 'Livros, exemplares, autores,<br/>editoras, categorias e contas', L, 354, 242, 83)
node('CIRCULAÇÃO', 'Self-checkout, balcão,<br/>comprovantes e devoluções', R-242, 354, 242, 83)
arrow(L+121, 437, L+121, 468)
arrow(R-121, 437, R-121, 468)
node('DAPPER / SQL PARAMETRIZADO', 'Comandos e transações da API', L, 468, 242, 62)
node('PROCEDURES TRANSACIONAIS', 'Regras + trava + gravação + log', R-242, 468, 242, 62)
arrow(L+121, 530, L+121, 563)
arrow(R-121, 530, R-121, 563)
node('SQL SERVER', '11 tabelas | PK/FK e CHECKs | índice único filtrado | auditoria com NEWID()', L, 563, WIDTH, 68)
para('<b>Fronteira de segurança:</b> somente a API acessa o banco. As telas não escolhem '
     'a identidade do autoempréstimo nem alteram diretamente a disponibilidade.', L, 657, WIDTH, 10.2)
para('<b>Estado atual:</b> execução local em HTTP no endereço de loopback. HTTPS, domínio, '
     'CORS e credenciais restritas precisam ser configurados antes de publicar.', L, 711, WIDTH, 10.2)
c.showPage()

header(3, 'Modelo relacional', 'Visão das 11 tabelas. Os arquivos SQL são a definição completa de campos, chaves e restrições.')
# Diagrama compacto do núcleo, com setas rotuladas por cardinalidade.
node('EDITORAS', 'PK IdEditora', L, 144, 153, 57)
node('CATEGORIAS', 'PK IdCategoria', L+177, 144, 153, 57)
node('AUTORES', 'PK IdAutor', R-153, 144, 153, 57)
node('LIVROS', 'PK IdLivro<br/>FK editora e categoria', L+55, 257, 225, 76)
node('LIVROS_AUTORES', 'PK composta<br/>FK IdLivro + IdAutor', R-173, 257, 173, 76)
arrow(L+76, 201, L+115, 257)
arrow(L+253, 201, L+220, 257)
arrow(R-76, 201, R-76, 257)
text('1:N', L+77, 219, 8.5, color=TEAL)
text('1:N', L+218, 219, 8.5, color=TEAL)
text('1:N', R-67, 219, 8.5, color=TEAL)
arrow(L+280, 295, R-173, 295)
text('1:N', L+295, 277, 8.5, color=TEAL)
node('EXEMPLARES', 'PK IdExemplar<br/>FK IdLivro | tombo único', L+55, 384, 225, 76)
arrow(L+165, 333, L+165, 384)
text('1:N', L+174, 349, 8.5, color=TEAL)
node('ITENS_EMPRESTIMO', 'PK IdItemEmprestimo<br/>FK empréstimo + exemplar<br/>Devolução por item', L+55, 516, 225, 90)
arrow(L+165, 460, L+165, 516)
text('1:N (histórico)', L+174, 479, 8.5, color=TEAL)
node('USUARIOS', 'PK IdUsuario<br/>Perfil, ativo e senha hash', R-173, 384, 173, 76)
node('EMPRESTIMOS', 'PK IdEmprestimo<br/>FK titular + operador<br/>Canal e prazo', R-173, 516, 173, 90)
arrow(R-87, 460, R-87, 516)
text('1:N / dois papéis', R-166, 478, 8.5, color=TEAL)
arrow(R-173, 560, L+280, 560)
text('1:N', L+295, 543, 8.5, color=TEAL)
node('TBL_LOG_SISTEMA', 'PK GUID (NEWID)<br/>FK usuário opcional + evento e instante', L, 651, 290, 78)
node('CONFIGURACOES', 'Uma linha: limite, prazo,<br/>atrasos e self-checkout', R-193, 651, 193, 78)
para('Log: usuário 1:N eventos; evento pode não ter usuário. Configuração não possui FK.', L, 744, WIDTH, 9.2, MUTED)
c.showPage()

header(4, 'Fluxo do self-checkout', 'O código de tombo identifica o exemplar físico. ISBN identifica a edição do livro, não sua cópia.')
steps = [
    ('1', 'Autenticar', 'POST /api/v1/auth/login. O token identifica o leitor ativo.'),
    ('2', 'Conferir os códigos', 'Consultar o exemplar por código e montar a lista para confirmação.'),
    ('3', 'Confirmar a retirada', 'POST /api/v1/self-checkout/emprestimos recebe apenas codigosExemplares.'),
    ('4', 'Revalidar no banco', 'Verificar identidade, política, atrasos, limite e disponibilidade atual.'),
    ('5', 'Gravar e devolver o comprovante', 'Empréstimo + itens + disponibilidade + log. Sucesso: HTTP 201.'),
]
y=144
for number, title, body in steps:
    panel(L, y, WIDTH, 72)
    text(number, L+15, y+17, 22, True, TEAL)
    text(title, L+53, y+10, 11.2, True, NAVY)
    para(escape(body), L+53, y+31, WIDTH-69, 9.5, max_height=33)
    if number != '5':
        arrow(L+26, y+72, L+26, y+86)
    y += 87
table([
    ('<b>Limite / prazo</b>', '3 exemplares pendentes e 14 dias; parâmetros provisórios, alteráveis pelo administrador.'),
    ('<b>Atomicidade</b>', 'Todos os itens são confirmados ou nenhum. Qualquer falha desfaz a transação.'),
    ('<b>Concorrência</b>', 'Trava transacional e índice único impedem duplicidade e protegem o limite total.'),
    ('<b>Devolução</b>', 'Equipe confere o exemplar; pode devolver parte dos itens. Finaliza após o último.'),
], 598, left_width=124, size=9.5)
c.showPage()

header(5, 'Executar e integrar', 'O pacote contém código-fonte, solução .NET, scripts SQL, requisições e testes reproduzíveis.')
y=section('Início local',
    'Pré-requisitos: .NET SDK 10, SQL Server, sqlcmd e PowerShell. Abra um terminal '
    'na pasta do projeto e execute <b>./scripts/Start-Local.ps1</b>. '
    'O script prepara o banco e, na primeira execução, pede a senha do administrador. '
    'Não existe senha padrão. O servidor fica em <b>http://127.0.0.1:5180</b>.', 145)
y=section('Acervo e primeiro empréstimo',
    'A demonstração inclui 3 títulos fictícios e 6 exemplares. Faça login como admin, '
    'cadastre uma conta LEITOR e autentique-se com ela. Envie '
    '<b>{&quot;codigosExemplares&quot;:[&quot;DEMO-BD-001&quot;]}</b> ao endpoint de self-checkout. '
    'Use o accessToken no cabeçalho Authorization: Bearer. Exemplos editáveis estão em '
    '<b>docs/requisicoes.http</b>.', y)
y=table([
    ('<b>Contrato da API</b>', '/openapi/v1.json, importável em ferramentas de teste. /health verifica o banco.'),
    ('<b>Leitor</b>', 'Consulta catálogo e política, faz autoempréstimo e consulta o próprio histórico/comprovante.'),
    ('<b>Bibliotecário</b>', 'Gerencia acervo, cadastra leitores, registra empréstimos no balcão e devoluções.'),
    ('<b>Administrador</b>', 'Inclui as funções de equipe, gerencia perfis/ativação, política e consulta auditoria.'),
    ('<b>Erros HTTP</b>', '400 dados; 401 sessão; 403 permissão; 404 inexistente/inacessível; 409 conflito; 422 regra de negócio; 429 limite de login.'),
], y, left_width=126, size=9.7)
section('Cuidados de segurança e publicação',
    'Senhas são hashes PBKDF2, e tokens duram 60 minutos. A conta ativa é revalidada '
    'em cada chamada protegida. Em Development, a chave JWT pode ser efêmera. '
    'Antes de publicar: usar HTTPS, chave persistente forte, credencial SQL restrita, '
    'certificado confiável, origens e host explícitos. Esta entrega não foi publicada.', y+23)
c.showPage()

header(6, 'Validação e próximos marcos', 'Resultados observados em 01/10/2026. Estes testes cobrem o backend, não a futura interface.')
table([
    ('<b>Compilação Release</b>', 'Concluída: zero erros e zero avisos; restauração com dependências travadas.'),
    ('<b>Testes HTTP</b>', '18 de 18 aprovados: autenticação, autorização, titularidade, regras e contratos.'),
    ('<b>Concorrência</b>', 'Duas pessoas / mesmo exemplar: só uma confirma. Mesmo leitor / dois pedidos: limite total preservado.'),
    ('<b>Rollback</b>', 'Códigos inválidos, itens já emprestados e autor inexistente não deixam gravação parcial.'),
    ('<b>Circulação</b>', 'Atrasos, manutenção, bloqueio do self-checkout, retorno parcial/final e novo empréstimo.'),
    ('<b>Integridade SQL</b>', '5 verificações: exclusividade, disponibilidade, cabeçalho/itens, titularidade do autoempréstimo e FKs.'),
], 145, left_width=132, size=10)
y=section('Como reproduzir',
    'Execute <b>dotnet build Biblioteca.slnx</b> e depois '
    '<b>./scripts/Test-Integration.ps1 -Python python</b>. '
    'O script cria banco exclusivo, usa credenciais efêmeras e encerra a API de testes. '
    'O banco permanece disponível para consulta. A execução registrada usou '
    '<b>BibliotecaTest_20261001091201</b>. O teste de atraso altera somente sua própria '
    'massa de teste.', 451)
y=section('Limitações conhecidas',
    'A trava global de circulação é apropriada para o MVP acadêmico, mas deve ser '
    'reavaliada para alto volume. Ainda não há testes de carga, recuperação de senha, '
    'renovação, reserva, multas ou confirmação idempotente. Em falha de rede após '
    'confirmar, consulte o histórico antes de repetir a operação.', y)
section('Referência e continuidade',
    'O DDL completo está em <b>database/001-schema.sql</b>; as transações, em '
    '<b>database/002-procedures.sql</b>. O README explica instalação e configuração. '
    'Próximos marcos: decidir a interface responsiva, implementar login e autoatendimento '
    'e validar as regras com o professor. Este PDF atualiza o planejamento v0.1.', y)
c.save()
print(OUTPUT)
