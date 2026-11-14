#!/usr/bin/env python3
"""Branche la clé de signature de release dans le build.gradle.kts généré par
`flutter create` (la CI l'appelle quand le secret de la clé existe).

Usage : sign_release.py android/app/build.gradle.kts
Attend : android/app/fractus-release.p12 et la variable KEYSTORE_PASSWORD au build.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
if 'create("release")' in src:
    print("Signature déjà branchée")
    sys.exit(0)

block = '''    signingConfigs {
        create("release") {
            storeFile = file("fractus-release.p12")
            storeType = "PKCS12"
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = "fractus"
            keyPassword = System.getenv("KEYSTORE_PASSWORD")
        }
    }

    buildTypes {'''
if "    buildTypes {" not in src or 'signingConfigs.getByName("debug")' not in src:
    print("build.gradle.kts inattendu : signature non branchée", file=sys.stderr)
    sys.exit(1)
src = src.replace("    buildTypes {", block, 1)
src = src.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")', 1)
open(path, "w", encoding="utf-8").write(src)
print("Signature de release branchée")
