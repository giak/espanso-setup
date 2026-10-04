# Vision — espanso

## Pourquoi ce projet existe

Espanso est installé sur cette machine et fait partie du poste de travail au
quotidien : une séquence de déclenchement, un `:brain`, un `:wf`. Le service
est donc critique — il touche à tous les champs de texte de toutes les
applications — et il s'est déjà dégradé sans prévenir.

Le 4 octobre 2026, un diagnostic demandé en une ligne — « vérifie qu'il est à
jour, il déconne » — a révélé quatre choses que personne ne savait :

1. la version installée était **2.2.1, sortie en décembre 2023**, soit deux
   versions mineures et six patchs de retard ;
2. l'installation était en double, avec un `.deb` **cassé** (`/usr/bin/espanso`
   ne démarrait pas) ;
3. le symptôme « il déconne » était un **mélange d'ordre des caractères** dans
   les applications Electron, sans aucun message d'erreur nulle part ;
4. la note d'installation du vault Obsidian décrivait une procédure **erronée**.

Le problème de fond n'était pas la version. C'est qu'un composant aussi
discret que l'expansion de texte avait tropics **sans propriétaire, sans
procédure written, sans état connu**, alors qu'il touche à tous les champs de
texte de toutes les applications.

Ce projet existe pour que ça n'ait plus de zone grise.

## Ce que ce projet change

**Un état vérifiable.** `scripts/espanso-check.sh` ne demande rien à personne :
il interroge le binaire, dpkg, systemd, le log du worker et le YAML, puis sort
en code 0 ou 1. On peut le brancher sur une vérification d'`agenda` et savoir
le lendemain matin si le service est tombé.

**Une procédure écrite et vérifiée.** `docs/` conserve le compte rendu
forensique de la migration 2.2.1 → 2.4.1 avec, pour chaque affirmation, sa
preuve : numéros de ligne dans le source Rust d'espanso, codes retour, sorties
de commande. Le rapport contient aussi ce qui **n'a pas** fonctionné — une
première tentative par AppImage, un binaire fantôme en `.deb`, un `package list`
cassé par une migration de dépendance — parce que les impasses valent autant que
les receipts.

**Une règle d'édition explicite.** Les matches sont maintained directement dans
`~/.config/espanso/match/base.yml`, versionné dans ce dépôt comme source de
vérité, avec la configuration globale documentée et un test de non-régression
avant sauvegarde. Aucune interface graphique tiers n'est requise.

## Ce que ce projet n'est pas

- Ce n'est pas un fork d'espanso. C'est une surcouche d'exploitation locale.
- Ce n'est pas un gestionnaire de packages d'expansion : les packages
  upstream restent gérés par `espanso package`, et leurs pièges sont documentés
  dans `docs/` plutôt que contournés.
- Ce n'est pas une collection de snippets. Les triggers restent dans le
  YAML d'espanso, au lieu où espanso les lit. Le dépôt en garde **une copie
  versionnée**, pas l'original — `~/.config/espanso` reste la vérité
  d'exécution.

## Pour qui

- Le propriétaire de la machine, quand un trigger ne se déclenche plus et qu'il
  faut savoir quoi regarder en premier.
- Un agent de code futur, qui doit pouvoir répondre à « quelle version, quel
  service, quels triggers » sans shell interactif et sans supposer.