# ErnMMUI

OpenMW UI replacer.

## Installing

Download the [latest version here](https://github.com/erinpentecost/ErnMMUI/archive/refs/heads/main.zip). The mod's Nexus page is [here](https://www.nexusmods.com/morrowind/mods/57315).

Extract to your `mods/` folder. In your `openmw.cfg` file, add these lines in the correct spots:

```ini
data="/wherevermymodsare/mods/ErnMMUI-main"
content=ErnMMUI.omwscripts
```

## Credits

- HayghinDaedricFont by Georg A. Duffner & M. Millar -- https://github.com/mmillar-bolis/HayghinDaedricFont (OFL-1.1 license)
- PCP myui by Qlonever (MIT)
- SnoopthDuckDuck Things (CC0)

## random notes


magick -background transparent -fill white -gravity center -size 32x32 +antialias -font "Hayghin-Daedric" label:s S.png


convert S.png \
  \( +clone -alpha extract -background gray -alpha shape \) \
  -geometry +1+1 \
  +swap -composite S_d.png



for f in *.png; do convert \
  \( "$f" -alpha extract -background gray -alpha shape \) \
  \( +clone -geometry +1+0 \) \
  \( +clone -geometry +0+1 \) \
  \( +clone -geometry +1+1 \) \
  "$f" \
  -background none -flatten \
  "./tmp/shadow_$f" && mv "./tmp/shadow_$f" "$f"; done
