"""Empacota somente os fontes e a documentação, sem binários, logs ou segredos locais."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
output = root.parent / 'biblioteca-v0.2.zip'
excluded_dirs = {'bin', 'obj', 'test-results', '__pycache__', '.git', '.vs', '.idea'}
excluded_names = {'appsettings.Local.json', 'appsettings.Development.json', 'secrets.json'}
allowed_extensions = {'.cs', '.csproj', '.json', '.slnx', '.md', '.sql', '.http', '.ps1', '.py', '.pdf'}
files = []
for path in sorted(root.rglob('*')):
    relative = path.relative_to(root)
    if not path.is_file() or path.is_symlink() or excluded_dirs.intersection(relative.parts):
        continue
    if path.name in excluded_names or path.name.startswith('.env'):
        continue
    if path.name != '.gitignore' and path.suffix.lower() not in allowed_extensions:
        continue
    files.append((path, f'biblioteca/{relative.as_posix()}'))

with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path, archive_path in files:
        archive.write(path, archive_path)
with ZipFile(output) as archive:
    assert archive.testzip() is None, 'Arquivo ZIP inválido.'
    assert len(archive.namelist()) == len(files)
    for required in ['README.md', 'Biblioteca.slnx', 'database/001-schema.sql',
                     'docs/arquitetura-v0.2.pdf', 'tests/smoke.py']:
        assert f'biblioteca/{required}' in archive.namelist(), required
print(f'{output}\n{len(files)} arquivos; {output.stat().st_size} bytes; integridade ZIP validada.')
