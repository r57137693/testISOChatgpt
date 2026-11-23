# Sillage 0.1.1

Sillage est une image live et installable d’Ubuntu 26.04 LTS avec Xfce sous X11 pour l’ASUS X756UXM. Le bureau est conçu pour l’Intel HD 520. Le pilote NVIDIA 580 signé et PRIME permettent de sélectionner la GTX 950M pour les jeux. Le bureau graphite et le fond inspiré du Jura sont inclus dans la session live et dans le système installé.

Cette version corrige la gestion automatique de l’Ethernet. Le workflow utilise QEMU avec une carte Intel PRO/1000 et un réseau NAT. Il vérifie le démarrage UEFI Secure Boot, l’ouverture du bureau, l’obtention d’une adresse IPv4 par DHCP et l’accès HTTPS à Internet. Il contrôle aussi que le disque témoin reste intact. L’installation Calamares et les essais sur l’ASUS sont des contrôles manuels.

## Construire avec GitHub depuis Windows

1. Télécharge les sources du dépôt et décompresse-les. Dans le dossier du projet, tu dois voir `README.md`, `config`, `scripts`, `rootfs` et `.github`.
2. Sur [GitHub](https://github.com/new), crée un dépôt **privé** nommé `sillage`. Laisse les options README, `.gitignore` et licence décochées. Copie l’adresse HTTPS du dépôt.
3. Ouvre PowerShell dans le dossier `sillage`. Si `git --version` échoue, installe Git avec `winget install --id Git.Git --exact`, puis rouvre PowerShell.
4. Exécute ces commandes. Remplace l’adresse d’exemple par celle de ton dépôt. Si Git réclame ton nom et ton e-mail, utilise les commandes qu’il affiche, puis relance le commit. La première connexion peut ouvrir GitHub dans ton navigateur.

   ```powershell
   git init -b main
   git add .
   git commit -m "Première version de Sillage"
   git remote add origin https://github.com/TON-COMPTE/sillage.git
   git push -u origin main
   ```

5. Dans le dépôt, ouvre **Actions → Construire Sillage → Run workflow**. Laisse le champ `snapshot` vide pour le premier essai. Garde les journaux de l’étape qui échoue si l’exécution s’arrête.
6. Quand toutes les étapes sont vertes, ouvre le lien de téléchargement dans le résumé de l’exécution. Il mène au brouillon de version dans **Releases**. Le brouillon suffit pour télécharger les fichiers. Télécharge l’ISO et son fichier `.sha256`.

GitHub limite chaque fichier d’une version à 2 Gio. Si l’image dépasse cette taille, télécharge toutes les parties `.part-000`, `.part-001`, etc., avec le fichier `.sha256` et `Assembler-ISO.ps1`, dans un même dossier. Ouvre PowerShell dans ce dossier et lance `powershell -ExecutionPolicy Bypass -File .\Assembler-ISO.ps1`. Ce réglage s’applique au processus qui exécute le script. Le script vérifie le SHA‑256 avant de rendre l’ISO disponible.

Pour vérifier une ISO téléchargée en un fichier, ouvre le `.sha256` dans le Bloc-notes et compare le code avec la sortie de cette commande.

```powershell
Get-FileHash -Algorithm SHA256 .\sillage-0.1.1-amd64.iso
```

## Premier test en machine virtuelle

Dans VirtualBox, crée une VM Ubuntu 64 bits avec **2 processeurs, 4 Go de RAM et un disque virtuel de 30 Go**. Active **UEFI** avant le premier démarrage et attache l’ISO au lecteur optique virtuel. Dans **Réseau → Adaptateur 1**, sélectionne **NAT** et vérifie que le câble virtuel est connecté. Le workflow fournit un contrôle Secure Boot séparé via QEMU. Garde les disques physiques hors de la configuration de la VM.

1. Démarre **Essayer Sillage**. Vérifie que le bureau s’ouvre. Lance `sillage-diagnostic` dans un terminal. Le disque virtuel doit apparaître avec `RO=1`, et le système doit afficher `zram0`.
2. Redémarre sur l’ISO et choisis **Installer Sillage**. Une fois sur le bureau, cherche **Installer Sillage** dans le menu et sélectionne le disque **virtuel**. Termine l’installation, retire l’ISO du lecteur virtuel et redémarre. L’entrée UEFI peut s’appeler `ubuntu` à cause du chemin utilisé par GRUB signé. Vérifie que ton compte peut ouvrir la session et que `sillage-diagnostic` affiche le noyau, zram et le fichier d’échange.

## Premier test sur l’ASUS

Grave l’ISO sur une clé USB de 8 Go ou plus avec [Rufus](https://rufus.ie/). Cette opération efface la clé sélectionnée. Choisis le **mode DD** si Rufus te le propose. Sur l’ASUS éteint, branche la clé puis appuie plusieurs fois sur **Échap** dès l’allumage pour ouvrir le menu de démarrage. Choisis la ligne **UEFI** de la clé.

Choisis **Essayer Sillage — disques en lecture seule**. La session place les périphériques de stockage en lecture seule et masque leur montage dans le bureau. Vérifie le SSD SanDisk avec `lsblk -o NAME,MODEL,SIZE,RO,TRAN,MOUNTPOINTS`. La colonne `RO` doit valoir `1` pour le SSD et ses partitions, et aucune partition Windows ne doit apparaître montée. Si l’écran reste noir, redémarre sur le **secours Intel** depuis le même menu.

Teste le Wi-Fi, le son, la luminosité, le pavé tactile, les touches Fn, la veille et le HDMI. Pour le diagnostic graphique, lance `sillage-diagnostic --nvidia`. Le premier rendu X11 doit indiquer Intel et la commande de test PRIME doit indiquer NVIDIA. Évite l’entrée **Installer** sur l’ASUS pendant les premiers essais.

## Jeux et comparaison

Pour installer un lanceur, ouvre **Jeux sur NVIDIA** dans le menu. Les clients sont téléchargés depuis Flathub et les jeux via ton compte Steam, Epic ou Microsoft. Une installation lancée pendant la session live utilise l’espace de travail temporaire et disparaît au redémarrage. Un système installé sur disque permet des mesures répétables.

Pour Minecraft, utilise Prism Launcher, sélectionne le Java requis par la version et pars sur 3 Gio de mémoire maximale. Vérifie dans F3 que la GTX 950M fait le rendu. Pour comparer deux systèmes, garde le même monde, la même résolution, la même distance d’affichage et le même shader, et fais trois passages identiques. Pour Rocket League, teste l’entraînement puis la connexion en ligne. Les profils d’alimentation accessibles dépendent du matériel. `powerprofilesctl list` affiche les profils détectés.

## Construire localement sur Linux

Utilise une machine Ubuntu 26.04 x86‑64, idéalement une VM avec environ 25 Go libres. Installe les outils et lance la construction.

```bash
sudo apt-get update
sudo apt-get install mmdebstrap ubuntu-keyring xorriso squashfs-tools curl gpg grub-common \
  kmod initramfs-tools-core qemu-system-x86 ovmf fdisk e2fsprogs desktop-file-utils python3-yaml zstd
bash scripts/check-source.sh
sudo bash scripts/build.sh
bash scripts/test-iso.sh dist/sillage-0.1.1-amd64.iso
```

`config/release.env` fixe l’instantané Ubuntu et l’image officielle Lubuntu 26.04.1 utilisée uniquement comme gabarit de démarrage signé. Le build assemble son propre système depuis les paquets, reconstruit l’initramfs et remplace le système live. Firefox provient du dépôt signé de Mozilla et sa version résolue figure dans `filesystem.manifest`. Un build refait avec le même instantané Ubuntu peut embarquer une version différente de Firefox. Le projet fournit le manifeste et la recette de construction, sans promettre deux ISO identiques octet pour octet.
