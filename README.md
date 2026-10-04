# espanso — exploitation locale

Supervision, documentation et édition des matches d'espanso sur
**Linux Mint 22.3 (Cinnamon, session X11)**.

- **`VISION.md`** — pourquoi ce projet existe.
- **`docs/`** — comptes rendus forensiques datés, avec preuves.
- **`scripts/espanso-check.sh`** — état de santé déterministe, exit 0/1.
- **`match/base.yml`** — copie versionnée des triggers. **Source de vérité pour
  l'édition**, pas le fichier lu par espanso à l'exécution.

## État vérifié au 2026-10-04

| | |
|---|---|
| Version | **2.4.1** (dernière release upstream, 2026-09-02) |
| Binaire | `/usr/bin/espanso` — instance unique, deb officiel `dpkg espanso 2.4.1-1` |
| Service | `espanso.service` systemd utilisateur, `ExecStart=/usr/bin/espanso launcher`, active + enabled |
| Session | X11 (`XDG_SESSION_TYPE=x11`) — `X11AppInfoProvider` / `X11Source` / `X11ProxyInjector` / `X11Clipboard` |
| Clavier | `fr` (AZERTY) |
| Matches | 10, dans `~/.config/espanso/match/base.yml` |
| Config runtime | `~/.config/espanso/` — ne pas déplacer, ne pas versionner tel quel |
| GUI tiers | aucun (le Flatpak `io.unobserved.espansoGUI` a été désinstallé le 2026-10-04) |

## État de santé

```bash
./scripts/espanso-check.sh
```

Sortie `OK` + exit 0 si tout est conforme, liste des anomalies + exit 1 sinon.
Vérifie : version, provenance du paquet, service systemd, worker vivant, absence de
process zombie, `inject_delay`, nombre de triggers, erreurs du log.

## Commandes utiles

```bash
espanso status                      # daemon vivant ?
espanso log                         # log du worker (X11 providers, erreurs)
espanso match list                  # triggers chargés
espanso path                        # chemins config / packages / runtime
espanso edit                        # ouvrir les YAML dans $EDITOR
espanso service status              # service systemd
```

`espanso.log` n'est pas versionné : `~/.cache/espanso/espanso.log`.

## Éditer un trigger

1. Écrire la modification dans **`match/base.yml`** de ce dépôt (source de vérité).
2. Copier vers la config runtime :

   ```bash
   install -m 644 match/base.yml ~/.config/espanso/match/base.yml
   ```

   Ou `~/.config/espanso/match/base.yml` directement si la config runtime
   n'a pas divergé — comparer avec `diff` d'abord.

3. Le worker recharge **automatiquement** (`--start-reason config_changed`).
   Aucune commande de restart n'est nécessaire ; `espanso match list` suffit à
   vérifier que le trigger est chargé.

## Pièges documentés

Ces quatre points ont coûté du temps et se reproduiront. Détail et preuves dans
`docs/`.

1. **La doc d'install promet un `sha256` qui n'existe pas.** Pour la v2.4.1,
   `espanso-debian-x11-amd64-sha256.txt` renvoie un 404 — aucun des 6 assets
   publiés n'a de checksum. L'intégrité ne peut être contrôlée que par la taille
   et le checksum interne dpkg.
2. **`inject_delay: null` casse les applications Electron.** Délai 0 entre
   chaque événement clavier `XSendEvent` → Chromium réordonne les caractères.
   Symptôme : même longueur, même jeu de caractères, ordre mélangé.
3. **La 2.4.0 a cassé `espanso package list`.** Migration `serde_yaml 0.8` →
   `serde_norway 0.9` : l'enum `PackageSource` à tag externe exige désormais un
   tag YAML. Tout `_pkgsource.yml` écrit avant la 2.4.1 est illisible.
4. **`dpkg -l` affiche `un` pour les libs wx alors qu'elles sont installées.**
   Ubuntu 24.04 a renommé les libs wxWidgets en `t64` ; `libwxgtk3.2-1` se résout
   en `libwxgtk3.2-1t64`. C'est aussi pourquoi l'ancien deb 2.2.1 ne démarrait
   pas : il exigeait wxWidgets **3.0**, absent de noble.

## Méthode d'installation (procédure correcte)

```bash
wget https://github.com/espanso/espanso/releases/latest/download/espanso-debian-x11-amd64.deb
sudo apt install ./espanso-debian-x11-amd64.deb
espanso service register
espanso start
```

Sur Ubuntu/Debian **X11** la doc officielle classe le **deb** comme méthode
recommandée et l'AppImage comme méthode « autres distros ». Voir
`~/Documents/Obsidian Vault/espanso-installation.txt` pour la version courte.