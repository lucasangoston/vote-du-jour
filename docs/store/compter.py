"""Compte les caractères des blocs ```text des fiches stores.

Usage : python3 docs/store/compter.py
Affiche, pour chaque bloc, le titre qui le précède et sa longueur en
caractères Unicode (ce que comptent App Store Connect et la Play Console).
"""

import pathlib
import re

here = pathlib.Path(__file__).parent
for fiche in ("app-store.md", "google-play.md"):
    texte = (here / fiche).read_text(encoding="utf-8")
    print(f"== {fiche}")
    titre = ""
    for bloc in re.finditer(r"^(?P<ind> *)```text\n(?P<corps>.*?)^(?P=ind)```", texte, re.M | re.S):
        avant = texte[: bloc.start()]
        lignes = [l for l in avant.splitlines() if l.startswith(("#", "- **"))]
        titre = lignes[-1].strip() if lignes else ""
        ind = len(bloc["ind"])
        corps = "\n".join(l[ind:] for l in bloc["corps"].rstrip("\n").split("\n"))
        print(f"{len(corps):5d}  {titre}")
