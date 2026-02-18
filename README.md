# 🐧 Nobara Linux Utilities

[![Linux](https://img.shields.io/badge/Linux-Nobara-blue?logo=linux&logoColor=white)](https://nobaraproject.org/)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/rufusg08/nobara-btw/graphs/commit-activity)

> 🛠️ Scripts inteligentes para otimização e recuperação do Nobara Linux (IdeaPad 330 15IKB)

---

## 📋 Índice

- [Scripts Disponíveis](#-scripts-disponíveis)
  - [🧹 ck.sh - Clean Kernel](#-cksh---clean-kernel)
  - [🔧 fixboot.sh - Fix Boot Intel UHD 620](#-fixbootsh---fix-boot-intel-uhd-620)
  - [📹 wc.sh - Webcam Controller](#-wcsh---webcam-controller)
- [Configurações EasyEffects](#-configurações-easyeffects)
- [Instalação](#-instalação)

---

## 🔧 Scripts Disponíveis

### 🧹 `ck.sh` - Clean Kernel

Limpeza inteligente do sistema Nobara.

**Funcionalidades:**
- Remove kernels antigos (mantém atual + backup)
- Limpa cache DNF/PackageKit
- Remove pacotes órfãos
- Limpa logs antigos (>7 dias)
- Otimiza espaço em disco

**Uso:**
```bash
chmod +x ck.sh && ./ck.sh
```

---

### 🔧 `fixboot.sh` - Fix Boot Intel UHD 620

**⚠️ CORREÇÃO PARA TELA PRETA APÓS UPDATES** (Lenovo IdeaPad 330 15IKB 81FE)

#### 🚨 Quando usar:
- Tela preta com `_` piscando após GRUB
- Sistema não inicia após `dnf update`
- Intel UHD 620 com conflitos no kernel

#### 📝 Como usar (PASSO A PASSO):

**1. No GRUB (tela de boot):**
   - Pressione `E` para editar
   - Localize a linha que começa com `linux`
   - **APAGUE** todos os parâmetros `i915.*` e `quiet splash`
   - **ADICIONE** no final: `nomodeset 3`
   - Pressione `Ctrl+X` para bootar

**2. No terminal (modo texto):**
```bash
# Login com seu usuário
chmod +x fixboot.sh
./fixboot.sh
```

**3. Escolha SIM para aplicar correção**

#### ✅ O que o script faz:

**Correção Permanente:**
- Remove `i915.fastboot=1` (causa tela preta)
- Adiciona parâmetros estáveis: `i915.enable_psr=0 i915.enable_dc=0 pcie_aspm=off`
- Atualiza drivers Mesa Wayland
- Reinstala KWin Wayland compositor
- Cria configuração permanente em `/etc/modprobe.d/`
- Regenera initramfs com módulos i915 corretos
- **Preserva todas customizações** (temas, widgets, configs)

**Resultado:**
- ✅ Boot normal restaurado
- ✅ Wayland funcionando
- ✅ Correção sobrevive a updates
- ✅ Suas customizações intactas

**Uso:**
```bash
chmod +x fixboot.sh
./fixboot.sh
# SIM = aplica correção | NÃO = cancela
```

---

### 📹 `wc.sh` - Webcam Controller

Controle inteligente da webcam com proteção contra desativação acidental.

**Funcionalidades:**
- Ativa/desativa webcam com segurança
- Detecta processos usando câmera
- Verifica drivers automaticamente
- Previne desativação durante uso

**Uso:**
```bash
chmod +x wc.sh && ./wc.sh
```

---

## 🎵 Configurações EasyEffects

Perfis de áudio otimizados para Nobara.

### 📁 Localização
```
~/.var/app/com.github.wwmm.easyeffects/data/easyeffects/
├── output/CustomBass.json  # Alto-falantes
└── input/Mic.json          # Microfone
```

### Perfis:

**🎸 CustomBass.json** (Output)
- Graves profundos otimizados
- Compressor + Limiter
- Ideal: eletrônica, hip-hop, rock

**🎤 Mic.json** (Input)
- Noise reduction avançado
- Gate anti-ruído
- Clareza vocal
- Ideal: streaming, calls, podcasts

**Instalação:**
```bash
cp CustomBass.json ~/.var/app/com.github.wwmm.easyeffects/data/easyeffects/output/
cp Mic.json ~/.var/app/com.github.wwmm.easyeffects/data/easyeffects/input/
```

---

## 📥 Instalação
```bash
# Clone o repositório
git clone https://github.com/rufusg08/nobara-btw.git
cd nobara-btw

# Torne scripts executáveis
chmod +x ck.sh fixboot.sh wc.sh

# (Opcional) Copie configs EasyEffects
cp CustomBass.json ~/.var/app/com.github.wwmm.easyeffects/data/easyeffects/output/
cp Mic.json ~/.var/app/com.github.wwmm.easyeffects/data/easyeffects/input/
```

---

## ⚙️ Requisitos

**Sistema:** Nobara Linux 38+ / Fedora / KDE Plasma

**Dependências:**
```bash
sudo dnf install dnf-utils v4l-utils
flatpak install flathub com.github.wwmm.easyeffects
```

---

## 🤝 Contribuindo

1. Fork o projeto
2. Crie branch: `git checkout -b feature/NovaFuncionalidade`
3. Commit: `git commit -m 'Add feature'`
4. Push: `git push origin feature/NovaFuncionalidade`
5. Abra Pull Request

---

## 📜 Licença

MIT License - Veja [LICENSE](LICENSE)

---

## 📞 Suporte

- 🐛 [Issues](https://github.com/rufusg08/nobara-btw/issues)
- 💬 [Discussions](https://github.com/rufusg08/nobara-btw/discussions)

---

<div align="center">

**⭐ Se ajudou, deixe uma estrela! ⭐**

Feito com ❤️ para Nobara Linux | Testado em IdeaPad 330 15IKB

[⬆ Voltar ao topo](#-nobara-linux-utilities)

</div>
