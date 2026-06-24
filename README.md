# Alpine APK Packer Repository

**Repo for some packages that can't go to aports**
📦 [https://cakgok.github.io/alpine-apk-packer/](https://cakgok.github.io/alpine-apk-packer/)

This repository targets Alpine `edge` on `x86_64`. Packages containing Python
extensions are tied to edge's current Python ABI and are not compatible with
stable Alpine branches.

---

## 🧩 To-Do List

- [ ] **Make noarch packages actually noarch**  
  Currently, all packages are tagged as `x86_64` to keep the repo script simpler.
- [ ] **Update repo indexer script**  
  Add support for handling `noarch` packages properly.
- [ ] **Pack `scraparr`**  
- [ ] **Fix action rolling cache**  
- [ ] **Fix incorrect detection logic when `pkgrel` is bumped**  

---
