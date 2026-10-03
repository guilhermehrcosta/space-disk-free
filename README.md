# Space Disk Free

App de barra de menus para macOS que mostra onde o espaço em disco está sendo consumido e oferece limpeza segura.

- **Ícone na barra de menus** com o espaço livre (fica em alerta acima de 90% de uso).
- **Limpeza**: categorias conhecidas (Lixeira, caches, logs, Xcode, simuladores, npm/Gradle/Cargo/Maven, Homebrew, Docker, backups de iPhone, Downloads) com tamanho e ação de um clique, sempre com confirmação.
- **Explorar**: maiores pastas da pasta pessoal, do disco inteiro ou de qualquer pasta, com navegação por níveis, "Mostrar no Finder" e "Mover para a Lixeira".

Requer macOS 14+.

## Instalar

Baixe o `SpaceDiskFree-<versão>.dmg` em **Releases**, abra-o e arraste o app para **Aplicativos**.

O app não é assinado com Developer ID, então o macOS bloqueia a primeira abertura. Para liberar, tente abrir o app uma vez, vá em **Ajustes do Sistema › Privacidade e Segurança** e clique em **Abrir Mesmo Assim**. Também dá para liberar pelo Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Space Disk Free.app"
```

## Publicar uma versão

No GitHub, crie um release com uma tag `vX.Y.Z` e publique. A action [release.yml](.github/workflows/release.yml) roda os testes, gera o `.dmg` universal (Apple Silicon e Intel) e anexa ao release.

## Compilar e rodar

Requer o Xcode.

```sh
make run       # compila e abre build/Space Disk Free.app
make install   # copia para /Applications e abre
make dmg       # gera build/SpaceDiskFree-<versão>.dmg universal
make test      # testes do DiskCore (Swift Testing)
make lint      # swift format lint (o CI usa o mesmo)
make format    # formata o código
```

## Arquitetura

```
Sources/
  DiskCore/            # lógica pura, sem UI, coberta por testes
    SizeCalculator     # tamanho alocado via fts(3): rápido, sem seguir symlinks, sem cruzar volumes, hard links contados 1x
    CleanupCategory    # catálogo de categorias e estratégia de cada uma
    Cleaner            # executa a limpeza e mede o espaço liberado
    SafetyPolicy       # o que nunca pode ser apagado, independente da UI
    DirectoryLister    # filhos diretos de uma pasta, para o explorador
    VolumeStatus       # capacidade e espaço livre do volume
  SpaceDiskFree/       # app SwiftUI (MenuBarExtra)
    AppState           # estado principal, varredura das categorias, confirmações
    ExplorerModel      # navegação e medição paralela (4 por vez) das subpastas
    Views/
```

### Estratégias de limpeza

| Estratégia       | Efeito                                         | Usada em                                  |
|------------------|------------------------------------------------|-------------------------------------------|
| `deleteContents` | apaga permanentemente o conteúdo, mantém a pasta | caches, logs, DerivedData, Device Support |
| `trashContents`  | move para a Lixeira (reversível)               | Xcode Archives                            |
| `emptyTrash`     | esvazia a Lixeira (via Finder se sem permissão) | Lixeira                                   |
| `command`        | roda a ferramenta oficial num shell de login    | `brew cleanup`, `simctl`, `docker prune`  |
| `review`         | nada automático, abre no Explorar               | Downloads, backups de iPhone              |

### Segurança

- `SafetyPolicy` bloqueia a home, `~/Library`, Documentos, Mesa, iCloud Drive (`Mobile Documents`), `Application Support`, `Containers` etc., e qualquer coisa fora da home (exceto apps em `/Applications`, que só podem ir para a Lixeira).
- Symlinks são resolvidos antes de apagar, para que um link não leve a limpeza para fora da home.
- Itens apagados pelo Explorar sempre vão para a Lixeira.

## Permissões

O app não usa sandbox, já que precisa ler a home inteira. Sem **Acesso Total ao Disco**, o macOS bloqueia algumas pastas (Mail, Safari, containers de outros apps, `~/.Trash`). Nesse caso o app mostra um aviso com atalho para *Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco*.

> A assinatura é ad-hoc. Cada recompilação gera uma nova identidade, e o macOS pode pedir as permissões de novo.
