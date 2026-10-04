# Migration espanso 2.2.1 vers 2.4.1 sur Linux Mint 22.3

Date : 2026-10-04. Demandé par l'utilisateur, réalisé par opencode.

Chaque affirmation est adossée à une preuve exécutable. Les points non
tranchés sont marqués `INCONCLUSIVE` plutôt que comblés.

---

## 1. Point de départ

Demande initiale, en une ligne : « j'ai espanso installé sur mon système Linux
Mint 22.3, mais vérifie qu'il est à jour. il déconne. »

Le symptôme n'a pas été précisé avant la fin de l'intervention. C'est un défaut
de la demande, pas de l'analyse : sans lui, le diagnostic s'arrêterait à la mise
à jour et passerait à côté de la cause réelle.

### 1.1 Version et provenance

```
$ espanso --version
espanso 2.2.1

$ which espanso
/usr/local/bin/espanso

$ readlink -f /usr/local/bin/espanso
/home/giak/opt/Espanso.AppImage
```

 Dernière version upstream au 2026-10-04 : **v2.4.1**, publiée le 2026-09-02
(`GET /repos/espanso/espanso/releases/latest`).

Retard : 2 versions mineures, 6 patchs. Versions sautées : 2.2.5, 2.2.6, 2.2.7,
2.2.8, 2.3.0, 2.4.0, 2.4.1. Le binaire datait de décembre 2023.

### 1.2 Anomalie 1, installation en double

```
$ dpkg -l | grep espanso
ii  espanso  2.2.1  amd64  Cross-platform Text Expander written in Rust

$ /usr/bin/espanso --version
/usr/bin/espanso: error while loading shared libraries:
libwx_gtk3u_html-3.0.so.0: cannot open shared object file: No such file or directory
```

Le deb 2.2.1 était installé mais **inopérant**. Comme `/usr/local/bin` précède
`/usr/bin` dans le `PATH`, c'est l'AppImage qui était réellement exécutée : le
deb n'était que du poids mort, plus une ambiguïté de résolution.

### 1.3 Anomalie 2, daemon déjà disparu une fois

```
$ systemctl --user status espanso
Active: active (running) since 2026-10-04 17:55:52   Main PID: 2062570 (AppRun)

$ espanso log | head -1
19:12:15 [daemon(2235192)] [INFO] reading configs from: ...
```

`AppRun` démarré à 17:55:52, daemon et worker démarrés à 19:12:15, et le log ne
contient que les entrées de 19:12 : le log a été recréé, donc le daemon de 17:55
avait disparu.

**Cause : INCONCLUSIVE.** Pas de coredump (`coredumpctl list espanso` ne renvoie
rien). Crash ou redémarrage manuel, non tranché. Sans impact sur la suite, le
mécanisme de redémarrage étant maîtrisé aujourd'hui.

### 1.4 Anomalie 3, process zombie

```
$ ps -o pid,ppid,stat,cmd -p 2235209
    PID    PPID STAT CMD
2235209 2235200 Z    [espanso] <defunct>
```

Enfant du worker, jamais `wait()`, donc fuite. Aucun process `tray` vivant : pas
d'icône dans la zone de notification.

### 1.5 Configuration, saine

```
$ espanso match list | wc -l
71
$ espanso status
espanso is running
```

`~/.config/espanso/config/default.yml` : format v2, `backend: inject`,
`keyboard_layout.layout: fr`, `inject_delay: null`, `disable_x11_fast_inject: null`.
Aucune erreur ni aucun avertissement dans le log.

---

## 2. Première tentative, par AppImage

La doc d'installation fut d'abord approximée par l'AppImage, jugée plus simple.
**C'était une erreur de méthode**, rappelée par l'utilisateur : la doc officielle
classe l'AppImage dans « Autres distros » et recommande le deb pour
Ubuntu/Debian en X11. Voir la section 4.

```
$ wget .../Espanso-X11.AppImage     # 20 317 376 o
$ systemctl --user stop espanso
$ install -m 755 Espanso-X11.AppImage ~/opt/Espanso.AppImage
$ systemctl --user start espanso
```

Résultat : 2.4.1 opérationnel, 71 matches conservés, 0 zombie. La migration de
fichier a réussi. Mais deux réserves :

- aucune empreinte publiée, donc intégrité non vérifiable, voir 6.1 ;
- `/usr/local/bin/espanso` continuait de pointer l'AppImage, donc le binaire
  réellement exécuté et l'unité systemd divergeaient.

Leçon : une migration réussie au sens « ça marche » peut rester fausse au sens
« c'est installé comme il faut ». Les deux vérifications sont distinctes.

---

## 3. Anomalie 4, régression `espanso package list`

Après le passage en 2.4.1 :

```
$ espanso package list
unable to list packages: unable to list packages

Caused by:
    0: unable to parse package source file
    1: invalid type: map, expected a YAML tag starting with '!' at line 2 column 1
```

### 3.1 Ce n'est pas un état préexistant

Test décisif avec le binaire 2.2.1 conservé :

```
$ ~/opt/Espanso.AppImage.bak-2.2.1 package list
Installed packages:

- ai-driven-dev-prompts - version: 2.0.34 (git: git@github.com:ai-driven-dev/prompts.git)
```

Fonctionnait en 2.2.1, cassé en 2.4.1 : **régression de l'upgrade**.

### 3.2 Cause prouvée dans le source

| Fichier | Fait |
|---|---|
| `espanso-package/src/archive/mod.rs:70-79` | `pub enum PackageSource` est un enum serde **à tag externe** (`Hub`, `Git{repo_url, repo_branch, use_native_git}`), sans `#[serde(tag=..)]` ni `untagged` |
| `espanso-package/src/archive/mod.rs:82-85` | lecture via `serde_norway::from_str` |
| `espanso-package/src/archive/read.rs:34-38` | idem pour `_pkgsource.yml`, avec le contexte d'erreur observé |
| `espanso-package/src/archive/util.rs:56` | écriture via `serde_norway::to_string` |
| `espanso-package/Cargo.toml:13` en v2.2.1 | `serde_yaml = "0.8.17"` |
| `espanso-package/Cargo.toml:13` puis `Cargo.toml:68` en v2.4.1 | `serde_norway.workspace = true`, soit `"0.9.42"` |

`serde_yaml 0.8` sérialise un enum à tag externe en **carte à clé simple**,
exactement le format du fichier sur disque :

```yaml
git:
  repo_url: "git@github.com:ai-driven-dev/prompts.git"
```

`serde_norway 0.9` exige un **tag YAML explicite** (`!git`), d'où le message
`expected a YAML tag starting with '!'`.

Conséquence : tout `_pkgsource.yml` écrit par un espanso inférieur ou égal à
2.2.x est illisible par 2.4.1. Les packages Hub, qui n'ont pas de
`_pkgsource.yml`, sont épargnés par le fallback `read.rs:40-42`.

### 3.3 Étendue réelle

| Commande | État | Source |
|---|---|---|
| `package list` | cassé | `cli/package/list.rs:30`, `archiver.list()` |
| `package update <nom>` et `update all` | cassé | `cli/package/update.rs:70`, `archiver.get()` |
| `package install` | fonctionne | écrit au format `serde_norway` |
| `package uninstall` | fonctionne | `uninstall.rs:35` puis `default.rs:141-151`, `remove_dir_all` sans parsing |
| expansion, donc daemon | non affectée | le worker charge les match files par un autre chemin |

### 3.4 Contre-experience

Une recherche GitHub sur `unable to list packages` ne renvoie qu'un résultat :
l'issue #1860, de février 2024. Son message d'erreur est **différent**
(`No such file or directory`) et elle portait sur un package installé à la main,
hors `espanso package install`. Conclusion à ne pas tirer : notre cas est une
erreur de désérialisation YAML, pas un fichier manquant.

### 3.5 Résolution

```
$ espanso package uninstall ai-driven-dev-prompts
package 'ai-driven-dev-prompts' uninstalled!
```

`remove_dir_all` ne parse pas `_pkgsource.yml`, donc le uninstall passe, et avec
lui la régression. 61 triggers retirés, les 10 triggers personnels intacts,
`espanso package list` affiche désormais `No packages found!`.

Réparation si le package redevient nécessaire : `uninstall` puis `install` avec
la 2.4.1, qui réécrit le fichier au format courant.

---

## 4. Passage à la méthode officielle, le deb

Rappelé par l'utilisateur, qui a lié la doc
`https://espanso.org/docs/install/linux/`. Extrait vérifié :

| Distribution | X11 | Wayland |
|---|---|---|
| Ubuntu/Debian | **DEB package (recommended)**, AppImage, Manual compilation | DEB package (recommended), Manual compilation |

Donc l'AppImage est la méthode « autres distros », pas la recommandée ici.

### 4.1 Téléchargement et intégrité

```
$ wget .../espanso-debian-x11-amd64.deb     # 4 792 712 o
$ wget .../espanso-debian-x11-amd64-sha256.txt
wget exit 8, fichier 0 octet
```

Écart doc/upstream : le fichier `sha256` que la doc promet pour vérifier le deb
**n'existe pas** en v2.4.1, la redirection mène à un 404. Les 6 assets de la
release :

```
   4926172  espanso-debian-wayland-amd64.deb
   4792712  espanso-debian-x11-amd64.deb
  16716368  Espanso-Mac-Universal.dmg
   7296664  Espanso-Win-Installer-x86_64.exe
   7774565  Espanso-Win-Portable-x86_64.zip
  20317376  Espanso-X11.AppImage
```

Aucun checksum. Contrôle d'intégrité obtenu : taille identique à celle de l'API
GitHub, `--version` fonctionnel, checksum interne dpkg. C'est **plus faible**
qu'une empreinte. Limite assumée, pas une validation.

### 4.2 Piège, les dépendances wxWidgets

```
$ dpkg -l libwxgtk3.2-1 libwxbase3.2-1
un  libwxbase3.2-1  <aucune>  <aucune>
un  libwxgtk3.2-1   <aucune>  <aucune>

$ dpkg -l | grep libwx
ii  libwxgtk3.2-1t64:amd64   3.2.4+dfsg-4build1
ii  libwxbase3.2-1t64:amd64  3.2.4+dfsg-4build1
```

`un` ne veut pas dire absent. Ubuntu 24.04, noble, a renommé les libs wxWidgets
en `t64` pour la transition `time_t`. `apt` résout `libwxgtk3.2-1` vers
`libwxgtk3.2-1t64`. Un diagnostic hâtif aurait conclu à une dépendance cassée.

C'est aussi la cause du deb 2.2.1 cassé en 1.2 : il exigeait
`libwx_gtk3u_html-3.0.so.0`, c'est-à-dire wxWidgets **3.0**, que noble ne fournit
plus. Le deb 2.4.1 exige wxWidgets **3.2**, il démarre donc.

### 4.3 Installation

```
$ sudo apt install -y ./espanso-debian-x11-amd64.deb
$ sudo rm -f /usr/local/bin/espanso
```

La seconde commande est obligatoire : tant que le symlink
`/usr/local/bin/espanso` existe, il précède `/usr/bin/espanso` dans le `PATH` et
le deb reste inerte. `/usr/local/bin` est en `755 root:root`, donc opération
root.

Fait marquant : la commande avait été donnée avec `&&`, et le `rm` n'a pas été
exécuté, l'utilisateur n'ayant lancé que la première partie. Détecté au contrôle
suivant, `which espanso` renvoyant encore `/usr/local/bin`. Un `&&` n'est pas de
l'atomicité, c'est une hypothèse de succès.

### 4.4 Enregistrement du service

```
$ systemctl --user stop espanso
$ espanso service register
service file already exists, this operation will overwrite it
creating service file in "/home/giak/.config/systemd/user/espanso.service"
enabling systemd service
service registered correctly!

$ espanso start
espanso started correctly!
```

Unité finale :

```ini
[Unit]
Description=espanso

[Service]
ExecStart=/usr/bin/espanso launcher
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

`ExecStart` corrigé vers `/usr/bin/espanso`. À noter : le sous-commande caché
`launcher` existe bien en 2.4.1, `espanso/src/main.rs:159`, marqué
`AppSettings::Hidden`. Et `service start/stop/restart/status` ont migré sous
`espanso service ...` ; `espanso start` de premier niveau reste accepté mais
n'est plus listé dans `--help`.

### 4.5 Effet de bord utile

Le deb installe `/usr/share/applications/espanso.desktop` et
`/usr/share/pixmaps/espanso.png`, absents de l'install AppImage. C'est la
PR #2757 de la v2.4.1, « linux: install desktop file and icon ».

---

## 5. Le vrai symptôme, Freebuff et `inject_delay`

Le symptôme est enfin précisé : dans Freebuff, `:brain` produisait
`brtaorim etns challenge ` au lieu de `brainstorm et challenge `. Dans le
terminal, la même saisie donnait le bon résultat.

### 5.1 La signature

```
attendu : b r a i n s t o r m _ e t _ c h a l l e n g e _
obtenu  : b r t a o r i m _ e t n s _ c h a l l e n g e _
```

Même longueur, 24. **Même multiset de caractères**. Rien ne manque, rien n'est
faussé. C'est un mélange d'ordre.

L'observation élimine deux hypothèses d'un coup :

- **Pas un problème de layout clavier.** Le mapping AZERTY vers les touches a
  réussi. Un layout erroné produirait des caractères faux, pas les bons
  caractères dans le désordre.
- **Pas de perte de caractères.** Rien n'a été mangé par l'application.

Ce qui reste est un problème de **timing**.

Freebuff est bien une application Electron, de la famille Chromium :

```
$ xprop -id 117440516 WM_CLASS
WM_CLASS(STRING) = "freebuff", "Freebuff"
```

Le terminal où opencode tourne est immunisé : un terminal lit un flux d'octets,
insensible au timing des événements clavier synthétiques.

### 5.2 Mécanisme

Dans `espanso-inject/src/x11/default/mod.rs:477-519`, la fonction `send_string` :

```rust
let delay_us = options.delay as u32 * 1000;   // ligne 496

for record in records? {
    if options.disable_fast_inject {
        self.xtest_send_key(&record.main, true, delay_us);          // XTest
    } else {
        self.send_key(focused_window, &record.main, true, delay_us);  // XSendEvent
        self.send_key(focused_window, &record.main, false, delay_us);
    }
}
```

La config avait `inject_delay: null`, donc `options.delay = 0` donc
`delay_us = 0`. Et `disable_fast_inject: null` donc `false`, voir
`espanso-config/src/config/resolve.rs:215-216`, `unwrap_or(false)`.

Le chemin actif était donc `send_key(focused_window, ...)`, qui fait, lignes
379 à 408 :

```rust
XSendEvent(self.display, window, 1, 0, &mut event);
XFlush(self.display);
if delay_us != 0 { libc::usleep(delay_us); }   // jamais exécuté
```

Soit une rafale d'environ 48 événements synthétiques `XSendEvent`, sans aucune
pause, vers la fenêtre ciblée.

**Prouvé** : le délai est nul, et le chemin d'injection est `XSendEvent`.
**Inféré** : que Chromium et ses dérivés Electron réordonnent ce burst. Le
mécanisme interne exact n'a pas été instrumenté. L'inférence est la plus
économique compatible avec la signature du 5.1, mais ce n'est pas une mesure.

### 5.3 Le levier, et sa validation

```yaml
# ~/.config/espanso/config/default.yml
inject_delay: 10
```

Coût : environ 20 ms par caractère, appui plus relâchement, soit **480 ms pour
`:brain`**.

Preuve que ce levier fonctionne sur cette plateforme : l'issue #1321,
« `inject_delay:` and `key_delay:` don't behave as expected », où un
correspondant confirme sur **Linux Mint X11** que `inject_delay` fonctionne, et
que le problème ne concerne que Windows.

Application et vérification : le worker s'est relancé tout seul,
`--start-reason config_changed`, `inject_delay` vaut 10 dans le fichier, et
**l'utilisateur a confirmé que cela fonctionne**.

### 5.4 Escalade préparée, non appliquée

Si le symptôme revient, le commutateur suivant est
`disable_x11_fast_inject: true`, qui bascule de `XSendEvent` vers
`XTestFakeKeyEvent`, `default/mod.rs:425-441`, avec `xtest_release_all_keys`.

Coût réel et non négligeable : ce choix **force `undo_backspace` à `false`**,
`espanso/src/cli/worker/config.rs:186-189`. Espanso ne peut plus filtrer ses
propres événements XTest et bouclerait sur ses propres injections. Le backspace
ne supprimerait plus l'expansion entière.

`xdotool 3.20160805.1` est installé, donc l'injecteur de fallback est disponible
si `X11DefaultInjector` échoue.

---

## 6. Le GUI, évalué puis écarté

### 6.1 Ce qui a été examiné

`johannjdk/espanso-gui`, PySide6, GPL-3.0, dernière release **v1.2.0** du
2026-10-02.

| Contrôle | Résultat |
|---|---|
| SHA256 de `espanso-gui-all.deb` | **vérifié**, `SHA256SUMS` → `Réussi` |
| `postinst` / `postrm` | bénins, `update-desktop-database` et `gtk-update-icon-cache` |
| Contenu | Python pur, 13 modules, rien n'est téléchargé à l'install |
| Paquet PyPI | **n'existe pas**, `espanso-gui` et `espanso_gui` en 404 |

### 6.2 Pourquoi il est inutilisable ici

```
$ apt-get -s install ./espanso-gui-all.deb
espanso-gui : Dépend: python3-pyside6.qtwidgets mais il n'est pas installable ou
                       python3-pyside6 mais il n'est pas installable
E: Impossible de corriger les problèmes
```

PySide6 **n'existe pas dans Ubuntu 24.04**. Noble ne paquete que PySide2, donc
Qt 5 : `python3-pyside2.qt3dinput`, `libpyside2-py3-5.15t64`, et aucune série
`python3-pyside6.*`. Le `Depends` du deb est insatisfiable, et le script officiel
`scripts/install-linux.sh` fait exactement `apt install ./deb`, donc il échouerait
identiquement.

Le seul chemin restant était PySide6 par pip, soit 244 Mo téléchargés :
`PySide6_Essentials` 76,4 Mo, `PySide6_Addons` **167,0 Mo**, `shiboken6` 0,3 Mo,
`PySide6` 0,5 Mo.

Décision de l'utilisateur : ne pas installer, et gérer les matches en éditant le
YAML directement.

### 6.3 Un GUI déjà installé, et cassé

Un Flatpak nommé `espansoGUI`, `io.unobserved.espansoGUI`, version 23.10,
provenant de Flathub, release du 2023-10-25, 40,8 Mo. Ce n'est pas le projet
`johannjdk`, c'est un projet d'un autre auteur.

Il était pointé vers un répertoire vide :

```
~/.var/app/io.unobserved.espansoGUI/config/espansoGUI/egui_data.json
{"espanso_dir":"/home/giak/.var/app/io.unobserved.espansoGUI/config/espanso"}
```

Ce chemin ne contenait aucun fichier. Le Flatpak n'a donc jamais vu
`~/.config/espanso` ni les 10 triggers. Désinstallé, avec son répertoire
orphelin de 4,4 Mo de caches Mesa.

---

## 7. Nettoyage

| Cible | Décision | Taille |
|---|---|---|
| deb dpkg espanso 2.2.1, cassé | purgé | 12,3 Mo |
| `~/opt/Espanso.AppImage`, doublon | supprimé | 19,4 Mo |
| `~/opt/Espanso.AppImage.bak-2.2.1` | supprimé | 15,7 Mo |
| `/tmp/espanso-up/`, sources extraites, tarballs, deb, AppImage | supprimé | 257 Mo |
| package `ai-driven-dev-prompts` | désinstallé | sans objet |
| Flatpak `io.unobserved.espansoGUI` et son orphelin | désinstallé | 40,8 et 4,4 Mo |

Total **338 Mo** récupérés. `/tmp` est repassé de 257 Mo occupés à vide.

Aucune sauvegarde conservée : l'utilisateur a validé la suppression de
`~/opt/espanso-backup-20261004/`. Une restauration du package passerait par le
hub espanso ou par les saves borg du home.

---

## 8. État final vérifié

```
dpkg                    espanso 2.4.1-1 (ii)
which -a espanso        /usr/bin/espanso        instance unique
espanso --version       2.4.1
espanso status          espanso is running
systemctl --user        active / enabled
espanso match list      10
processus zombies       0
log                     0 ERROR
```

Une entrée `[ERROR]` historique datée 19:25:08 subsiste dans le log : c'est le
`package list` déclenché manuellement pendant le diagnostic du chapitre 3, pas un
état courant.

---

## 9. Enseignements

1. **Une signature de symptôme vaut mieux qu'une description.** « ça fait des
   lettres mélangées » n'aurait rien dit. La longueur identique et le multiset
   identique ont éliminé le layout et la perte de caractères en une seule
   observation.
2. **Une migration qui marche n'est pas une migration correcte.** Le passage à
   l'AppImage a fonctionné tout en laissant deux chemins d'exécution divergents.
   Il fallait vérifier « quelle instance est réellement exécutée », pas seulement
   « est-ce que ça expire ».
3. **`&&` n'est pas de l'atomicité.** La partie `rm` n'a pas tourné, et seule une
   vérification explicite l'a détecté.
4. **Un `dpkg -l` qui affiche `un` ne prouve pas une absence.** La transition des
   libs wx vers les noms `t64` sur noble produit exactement cette sortie, alors
   que les paquets sont installés.
5. **Une régression peut être masquée par l'abstraction.** Le daemon ne chargeait
   pas `_pkgsource.yml` du tout, donc la régression de la section 3 ne
   touchait pas l'expansion. Sans tester la commande métier, on aurait conclu à
   tort que la mise à jour était sans effet.
6. **Un symptôme non qualifié coûte plus cher qu'un diagnostic incomplet.** Il a
   fallu toute une intervention avant que « il déconne » devienne « les
   caractères sont mélangés dans une app Electron ».