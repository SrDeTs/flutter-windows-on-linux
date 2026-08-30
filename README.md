# LEIA!!

isso foi feito num final de semana inteiro usando a IA grátis que a equipe na época deu grátis pra muita gente hoje sabemos que era o GLM 5.3 (anteriormente Ox Alpha)

fiquei vários dias pesquisando forma de conseguir buildar pra windows estando no linux então consegui chegar nesse resultado não sei se são reproduzíveis ate que ponto

consegui ter exito nisso depois de um tempo porem notei que o build tende a ser um pouco maior do que nativo do Windows mas e pouca coisa

bom pelo menos pra min e melhor do que usar o Winboat, por falar nele eu uso ele apenas pra testar se ainda o app executa no windows, as builds feita no linux

logo abaixo o resto foi feito pela IA então e isso!

# Flutter Windows No Linux

Ferramentas e pesquisa comunitária para gerar aplicações Flutter Windows x64 a
partir de um host Linux.

> [!IMPORTANT]
> Este projeto é experimental e não é desenvolvido, mantido ou suportado pela
> equipe Flutter ou pelo Google. O resultado precisa ser testado em uma máquina
> Windows real antes de qualquer distribuição.

## Objetivo

O Flutter oferece suporte oficial para compilar aplicações Windows em um host
Windows. Este repositório explora uma rota alternativa para desenvolvimento,
CI e estudo:

1. compilar o kernel Dart no Linux;
2. executar o `gen_snapshot.exe` oficial do Flutter através do Wine;
3. compilar o runner e plugins compatíveis com LLVM-MinGW, CMake e Ninja;
4. usar um sidecar MSVC sob Wine para plugins sensíveis à ABI, quando necessário;
5. montar o bundle com assets, native assets e DLLs do aplicativo.

O projeto nasceu durante o desenvolvimento de um aplicativo real e foi aberto
para servir como base de estudo. Ele não pretende substituir `flutter build
windows` em ambientes de produção.

## Estado atual

- Arquitetura alvo: Windows x86_64.
- Host exercitado: Linux x86_64.
- CLI: `flutter_build` versão `0.1.0-dev`.
- Modos disponíveis: debug, profile e release.
- Saída: executável, `flutter_windows.dll`, plugins, `data/app.so`, assets e
  native assets.
- Build incremental para fontes CMake, kernel, AOT, sidecar MSVC e assets.
- Tradução de flags comuns do MSVC para Clang/MinGW.
- Patches isolados para incompatibilidades conhecidas de plugins.
- Verificação de DLLs nativas declaradas pelos plugins.

Mesmo quando a compilação termina, isso não comprova câmera, microfone,
notificações, WebRTC, codecs ou integrações COM/WinRT no Windows de destino.

## Estrutura do repositório

```text
.
├── flutter_build/     CLI Dart que orquestra o cross-build
├── msvc-wine/         ferramentas para preparar MSVC/Windows SDK sob Wine
├── build-windows.sh   exemplo avançado usado como referência
└── installer.nsi      exemplo de instalador NSIS
```

O `build-windows.sh` e o `installer.nsi` são exemplos originados de um projeto
real. Eles contêm nomes, plugins e caminhos específicos e devem ser adaptados
antes do uso em outro aplicativo.

## Como funciona

```text
Flutter/Dart no Linux
        │
        ├── frontend_server ────────────────> app.dill
        │
        ├── gen_snapshot.exe + Wine ───────> app.so
        │
        ├── LLVM-MinGW + CMake + Ninja ────> runner e plugins compatíveis
        │
        ├── MSVC sidecar + Wine (opcional) ─> plugins com ABI MSVC
        │
        └── flutter assemble ───────────────> assets e native assets
                                               │
                                               v
                                      bundle Windows x64
```

Componentes externos importantes:

- [Flutter](https://github.com/flutter/flutter)
- [LLVM-MinGW](https://github.com/mstorsjo/llvm-mingw)
- [Wine](https://www.winehq.org/)
- [msvc-wine](https://github.com/mstorsjo/msvc-wine)
- [CMake](https://cmake.org/) e [Ninja](https://ninja-build.org/)
- [NSIS](https://nsis.sourceforge.io/), opcional para instaladores

## Pré-requisitos

- Linux x86_64;
- Flutter e Dart disponíveis no `PATH`;
- CMake e Ninja;
- Wine 64-bit;
- LLVM-MinGW x86_64;
- Git, curl e ferramentas de extração;
- NSIS somente para gerar instalador;
- MSVC/Windows SDK e projeções C++/WinRT somente para a rota avançada.

Os nomes dos pacotes variam entre distribuições. Use os pacotes oficiais da sua
distribuição e execute `flutter_build doctor` para identificar ausências.

## Instalação da CLI

Clone o repositório e ative o pacote Dart local:

```bash
git clone https://github.com/SrDeTs/flutter-windows-on-linux.git
cd flutter-windows-on-linux/flutter_build
dart pub get
dart pub global activate --source path .
```

Garanta que os executáveis globais do Dart estejam no `PATH`:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Para tornar isso permanente, adicione a exportação ao arquivo de configuração
do seu shell.

## Uso básico

Dentro de um projeto Flutter que já tenha o scaffold Windows:

```bash
flutter create --platforms=windows .
flutter pub get
flutter_build doctor --allow-download
flutter_build windows --release
```

Saída padrão:

```text
build/win_cross/release/<nome_do_app>/
├── <nome_do_app>.exe
├── flutter_windows.dll
├── plugins e native assets
└── data/
    ├── app.so
    ├── icudtl.dat
    └── flutter_assets/
```

Comandos disponíveis:

```bash
flutter_build doctor
flutter_build precache
flutter_build windows --release
flutter_build windows --profile
flutter_build windows --debug
flutter_build clean
```

Consulte [flutter_build/README.md](flutter_build/README.md) para todas as opções
da CLI.

## Plugins complexos e sidecar MSVC

Plugins que usam WebRTC, LiveKit, ATL, C++/WinRT, Media Foundation ou bibliotecas
pré-compiladas podem não aceitar a ABI MinGW. Nesses casos, o builder possui uma
rota opcional que compila plugins selecionados com MSVC real através do Wine e
liga os import libraries ao executável MinGW.

Variáveis usadas pela rota avançada:

```bash
export SIDECAR_MSVC=1
export MSVC_ROOT="$HOME/.msvc2"
export CPPWINRT_INCLUDE_DIR="$HOME/.cppwinrt/include"
export WINEDEBUG=-all
```

Use `msvc-wine` seguindo as instruções e licenças do projeto upstream. O script
de exemplo mostra como informar `SIDECAR_IMPORT_LIBS`, mas sua lista deve conter
somente os plugins usados pelo seu aplicativo.

### Licenciamento do MSVC

Os scripts de `msvc-wine` são software livre, mas o MSVC e o Windows SDK
baixados por eles pertencem à Microsoft. O uso exige aceitar os termos da
Microsoft e os binários instalados não devem ser adicionados a este repositório
nem redistribuídos como parte dele.

## Empacotamento

O bundle produzido pode ser compactado em ZIP ou usado como entrada para NSIS.
Os arquivos `build-windows.sh` e `installer.nsi` demonstram esse fluxo, mas são
templates: altere nome do aplicativo, executável, lista de DLLs, diretórios e
metadados antes de publicar.

Este projeto não implementa assinatura de código. Um instalador destinado a
usuários finais deve ser assinado e validado separadamente.

## Limitações

- Não é uma ferramenta oficial do Flutter.
- O foco atual é somente Windows x64.
- Nem todo plugin Windows é compatível com LLVM-MinGW.
- Alguns plugins precisam de patches específicos ou do sidecar MSVC.
- Atualizações do Flutter, engine, plugins ou Windows SDK podem quebrar o fluxo.
- O build bem-sucedido no Linux não substitui testes em Windows.
- Windows ARM64 e builds universais ainda não são suportados.
- A configuração avançada ainda não é um instalador de um único comando.

## Desenvolvimento e testes

```bash
cd flutter_build
dart format lib bin test
dart analyze lib bin test
dart test
```

## Licenças e atribuições

- `flutter_build/` usa a licença Apache-2.0 presente em
  [flutter_build/LICENSE](flutter_build/LICENSE).
- `msvc-wine/` mantém sua licença ISC em
  [msvc-wine/LICENSE.txt](msvc-wine/LICENSE.txt).
- Flutter, LLVM-MinGW, Wine, Microsoft Visual C++/Windows SDK e NSIS possuem
  licenças próprias.

Antes de publicar uma versão formal do repositório, adicione também uma licença
na raiz que deixe claro o licenciamento dos arquivos de integração e exemplos.
