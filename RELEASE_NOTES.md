# Release Notes — SimpleCAD

---

## v2.2.0 — 22 mai 2026

Version centrée sur la sélection multiple et les finitions d'interface.

### Sélection multiple

- Nouveau rectangle de sélection avec l'outil **Sélection** : clic-glisser depuis une zone vide du canvas
- Sélection automatique de toutes les formes croisées par le rectangle, y compris les formes tournées
- Maintien de **Maj** pendant le rectangle de sélection pour ajouter au groupe sélectionné
- Déplacement groupé : glisser une forme déjà sélectionnée déplace désormais toutes les formes de la sélection

### Interface

- Icône de l'outil **Sélection** remplacée par un curseur de souris simplifié
- Fond dédié derrière les boutons rouge/jaune/vert de la fenêtre
- Fond des boutons de fenêtre adapté au mode clair/sombre système
- Coins arrondis sur le fond des boutons de fenêtre

### Plan de travail

- Règle horizontale réduite de 66 % en hauteur
- Règle verticale réduite de 66 % en largeur
- Graduations et labels des règles ajustés pour rester lisibles dans leur format compact

### Configuration requise

- macOS 26 ou ultérieur
- Architecture Apple Silicon ou Intel

---

## v2.1.0 — 22 mai 2026

Version centrée sur le confort d'édition, les repères visuels et la gestion de l'ordre des formes.

### Panneau des formes

- Réordonnancement fiable des formes par glisser-déposer dans le panneau de droite
- Indicateur d'insertion bleu au-dessus ou en-dessous de la forme ciblée pendant le glisser
- Synchronisation immédiate entre l'ordre du panneau et l'ordre d'affichage dans le canvas
- Historique dédié à la réorganisation des formes, compatible avec Annuler / Rétablir

### Plan de travail

- Ajout de règles horizontale et verticale autour du plan de travail
- Règles synchronisées avec le scroll et le zoom du canvas
- Lisibilité améliorée des graduations et des valeurs
- Correction d'un problème où l'ajout des règles pouvait masquer les formes du canvas
- Taille par défaut du canvas réduite à 16 000 × 16 000 px pour une navigation plus confortable

### Interface et raccourcis

- Marge gauche ajoutée autour du panneau d'outils pour mieux dégager la zone de travail
- Raccourcis des outils de base corrigés : `V`, `R`, `Q`, `C`, `E`, `T`, `L`
- Les raccourcis outils ignorent les champs de texte actifs pour préserver l'édition inline

### Configuration requise

- macOS 26 ou ultérieur
- Architecture Apple Silicon ou Intel

---

## v2.0.0 — 21 mai 2026

Version centrée sur l'import SVG, la rotation des formes et l'intégration visuelle macOS 26.

### Import SVG

- Centrage automatique du contenu SVG à l'ouverture, même lorsque les formes importées sont très éloignées de l'origine du fichier
- Zoom automatique adapté au contenu importé pour rendre l'ensemble du dessin visible dès l'ouverture
- Agrandissement du plan de travail si nécessaire afin de conserver une marge confortable autour du contenu importé

### Rotation des formes

- Nouvelle poignée de rotation autour des formes sélectionnées
- Rotation interactive autour du centre de la forme
- Maintien de **Maj** pendant la rotation pour contraindre l'angle par incréments de 15°
- Historique dédié aux rotations, compatible avec Annuler / Rétablir
- Export SVG des formes tournées via `transform="rotate(...)"` et métadonnées SimpleCAD
- Réimport des rotations enregistrées dans les SVG SimpleCAD

### Cotes et sélection

- Les cotes suivent désormais la rotation locale de la forme au lieu de rester alignées sur la boîte englobante horizontale
- Labels de cotes réorientés pour rester lisibles pendant la rotation
- Zones cliquables des cotes adaptées à leur orientation, avec édition inline conservée
- Poignées de sélection placées sur les coins et milieux réels de la forme tournée

### Apparence

- Fond du canvas compatible avec le mode sombre système
- Grille, poignées, fonds de labels et zone autour du plan de travail adaptés automatiquement au thème macOS
- Conservation des couleurs de formes existantes pour préserver le rendu des fichiers SVG

### Configuration requise

- macOS 26 ou ultérieur
- Architecture Apple Silicon ou Intel

---

## v1.0.0 — 18 mai 2026

Première version publique de SimpleCAD.

### Dessin

- **6 outils de tracé** : Rectangle, Carré (contraint), Cercle (contraint), Ellipse, Triangle isocèle, Ligne
- **Outil Sélection** : clic simple, Maj-clic pour multi-sélection, glisser pour déplacer
- Maintenir **Maj** pendant le tracé pour contraindre n'importe quelle forme en carré/cercle
- Prévisualisation en temps réel pendant le tracé (remplissage semi-transparent)
- Déplacement au pixel près avec les **touches fléchées**

### Propriétés des formes

- Couleur de **remplissage** et de **contour** via le sélecteur de couleur natif macOS (avec support de la transparence)
- **Épaisseur de contour** réglable de 0,5 à 50 px (champ + stepper)
- Application instantanée des propriétés à toute la sélection courante

### Annotations dimensionnelles

- Affichage des **cotes** (largeur × hauteur) autour de chaque forme sélectionnée
- Flèches et lignes d'extension mis à l'échelle pour rester lisibles à **tout niveau de zoom**
- Clic sur une cote : **édition inline** de la dimension dans l'unité du document (virgule ou point acceptés)

### Gestion des calques

- Panneau **Calques** avec liste ordonnée par plan de rendu
- **Glisser-déposer** pour réordonner les calques
- **Double-clic** pour renommer une forme inline
- Boutons Premier plan / Arrière-plan (panneau et menu)

### Historique

- Panneau **Historique** avec chronologie visuelle de toutes les actions
- **50 niveaux d'annulation** conservés en mémoire
- Clic sur n'importe quelle entrée pour sauter directement à cet état
- Annuler / Rétablir classiques (`⌘Z` / `⌘⇧Z`) et boutons dans la barre d'outils

### Navigation

- **Zoom** de 5 % à 1 600 % — boutons, raccourcis `⌘+` / `⌘-` / `⌘0`, pinch trackpad, pavé numérique
- **Pan** fluide : `Espace` + glisser
- Grille d'alignement affichable/masquable
- Centrage automatique sur les formes à l'ouverture d'un fichier

### Unités

- 8 unités supportées : **mm, cm, m, km, in, ft, yd, mi**
- Conversion basée sur le standard SVG 96 DPI
- Toutes les cotes, la barre de statut et les badges de la liste de calques respectent l'unité choisie

### Fichiers

- Format **SVG standard** — fichiers lisibles dans tout éditeur compatible SVG
- Métadonnées SimpleCAD préservées via l'espace de noms `simplecad` (type, nom, dimensions en mm, unité)
- Nouveau, Ouvrir, Enregistrer, Enregistrer sous (`⌘N` / `⌘O` / `⌘S` / `⌘⇧S`)
- Ouverture par glisser-déposer sur l'icône de l'application
- Indicateur visuel de modifications non enregistrées (point orange dans la barre de statut)

### Interface

- Barre d'outils verticale à gauche (grille 2 colonnes pour les formes)
- Panneau calques/historique vertical à droite
- Effet verre (`.glassEffect`) — interface discrète au profit du canevas
- Grand canevas de 32 000 × 32 000 px
- Barre de statut : outil actif, coordonnées et dimensions de la sélection, taille du canevas
- Fenêtre sans barre de titre, taille minimale 960 × 680 px

### Raccourcis clavier

| Action | Raccourci |
|--------|-----------|
| Outils | `V` `R` `Q` `C` `E` `T` `L` |
| Tout sélectionner / désélectionner | `⌘A` / `⌘D` |
| Supprimer | `⌫` |
| Déplacer (1 px) | `←` `→` `↑` `↓` |
| Annuler / Rétablir | `⌘Z` / `⌘⇧Z` |
| Zoom avant / arrière / 100 % | `⌘+` / `⌘-` / `⌘0` |
| Pan | `Espace` + glisser |
| Nouveau / Ouvrir / Enregistrer | `⌘N` / `⌘O` / `⌘S` |
| Enregistrer sous | `⌘⇧S` |

### Configuration requise

- macOS 14 Sonoma ou ultérieur
- Architecture Apple Silicon ou Intel
