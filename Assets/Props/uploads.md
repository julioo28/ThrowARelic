# Props voxel (Blender → Roblox)

Modélisés dans Blender (scène « TAR_Props », script texte `tar_voxel.py`), exportés en FBX ici,
envoyés comme modèles privés sur le compte Roblox 11970054340 (Open Cloud), puis rangés dans
`ReplicatedStorage/Props/<Nom>` (un MeshPart par couleur, couleur lue dans le nom `<Nom>_<RRGGBB>_<n>`).

| Prop | Asset ID |
|---|---|
| Saguaro | 118600792660759 |
| SaguaroTall | 116249282290342 |
| BarrelCactus | 79088213335623 |
| PricklyPear | 86954198847901 |
| Juniper | 134187432701993 |
| JuniperSmall | 90999001787199 |
| Sagebrush | 80388588558923 |
| BoulderA | 95835001197488 |
| BoulderB | 84383651542444 |
| Barrel | 80319269012536 |
| Crate | 127650949196450 |
| Wagon | 87003977650191 |
| MineCart | 117441232317221 |
| Signpost | 120704132232699 |
| CowSkull | 106296637261305 |
| Condor (v1, plat, remplacé) | 110937593507286 |
| Condor v2 — aigle détaillé, ailes articulées (`tools/voxel_eagle.py`, install `tools/install_condor.luau`, FBX `Condor_v2.fbx`) | 105667266627487 |
| Tumbleweed | 122000459033201 |

**v2 détaillée (24/11) — remplace les 16 props ci-dessus sauf Condor :** un seul asset `TAM_PropsV2`
**83186667019374** (voxels de 0,5 stud, 4 à 10 couleurs par prop, mêmes noms et mêmes dimensions).
Générateur `tools/voxel_props_v2.py` (Blender, scène TAM_PropsV2, FBX `TAM_PropsV2.fbx`), install
`tools/install_props_v2.luau` (remplace aussi les copies posées dans `Landscape/Props` et `Village`).
Les ids v1 ci-dessus restent en attribut `AssetIdV1` sur chaque modèle.

Pour modifier un prop : le retoucher dans Blender, réexporter le FBX, le renvoyer (nouvel asset),
puis remplacer le modèle du même nom dans `ReplicatedStorage/Props`.

## Objets 3D de la boutique (`ReplicatedStorage/ShopModels/<Id amélioration>`)

Affichés en rotation dans une vitrine 3D (ViewportFrame) sur chaque ligne de la boutique.

| Amélioration | Modèle Blender | Asset ID |
|---|---|---|
| Power | Shop_Power (haltère) | 71843611085615 |
| Magnet | Shop_Magnet (aimant fer à cheval) | 71216206801748 |
| Cable | Shop_Cable (treuil) | 139865092129018 |
| Clean | Shop_Clean (seau + éponge) | 77719291241123 |
| Museum | Shop_Museum (vitrine + relique) | 81850032419279 |
| Book | Shop_Book (livre, bouton Collection) | 119211399048761 |

## Sons d'interface (synthétisés, `Assets/Props/Sounds`)

| Clé Config.Sounds | Asset ID |
|---|---|
| UIHover | 72784439191136 |
| UIClick | 98592755580765 |
| UIPop | 112435490337374 |
| UIOpen | 76652428711679 |
| UICoin | 123867809974561 |
| UIBuy | 90476836956191 |
| UIError | 119201629811669 |
| UIDing | 72220612698567 |
| UIWhoosh | 122487120263056 |

## Trouvailles voxel (1 007 objets, 100 par lot)

| Lot | Asset ID |
|---|---|
| TAM_Relics_01 | 132101897945560 |
| TAM_Relics_02 | 133971262406581 |
| TAM_Relics_03 | 86994101493136 |
| TAM_Relics_04 | 111069271680350 |
| TAM_Relics_05 | 87345825633026 |
| TAM_Relics_06 | 135064882476825 |
| TAM_Relics_07 | 130109823415068 |
| TAM_Relics_08 | 96296892144015 |
| TAM_Relics_09 | 137644177774803 |
| TAM_Relics_10 | 87658092004942 |
| TAM_Relics_11 | 81366960968071 |

## Banc de développé couché

| Modèle | Asset ID |
|---|---|
| TAM_BenchPress_v2 (BenchPress, Barbell, Plate1..6) | 101704772589476 |
| TAM_BenchPress (v1, barre trop courte, inutilisé) | 114117736773540 |

## Coffres au trésor

| Modèle | Asset ID |
|---|---|
| TAM_Chests (Chest_<rareté> + Chest_<rareté>Lid, 9 raretés) | 125838354980161 |
