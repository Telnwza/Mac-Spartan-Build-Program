# เตรียม repository และ release

## เลือก source ที่จะอัปโหลด

```sh
zsh prepare_repository.sh
```

ใช้โฟลเดอร์ที่แสดงใน `REPOSITORY_PATH` เป็น root ของ GitHub repository
ชุดนี้คัดเฉพาะ source, resources, tests, docs, license และ GitHub configuration
ไม่ได้รวม build เก่า, Docker image, installer, cache หรือ Git history
อย่าใช้โฟลเดอร์รวมหลายโปรเจกต์ที่อยู่เหนือ source นี้เป็นชุดอัปโหลด

สคริปต์ไม่ init, add, commit, push หรือสร้าง repository ให้เอง
repository ปลายทางคือ [https://github.com/Telnwza/Mac-Spartan-Build-Program](https://github.com/Telnwza/Mac-Spartan-Build-Program)
README เตรียมลิงก์สำหรับ tag `v2.4.0` ไว้แล้ว ลิงก์ดาวน์โหลดจะใช้ได้หลังเผยแพร่ release
คำอธิบาย repository ที่เตรียมไว้:

> Build VHDL, map pins, and program Spartan FPGA boards on macOS with Vivado in Docker and openFPGALoader.

## ตรวจชุดที่คัดออกมา

จาก root ของชุด source ที่จะเผยแพร่:

```sh
zsh diagnostics/check_build_workflow.sh
zsh build_app.sh
```

ใช้ผลจากชุดนี้เป็น release artifact เพื่อยืนยันว่าไฟล์ที่เผยแพร่ครบสำหรับ build
ทดสอบกับ Mac อีกเครื่องด้วยไฟล์ที่ดาวน์โหลดจาก release จริง แล้วบันทึกผลเพิ่มใน
[TESTING.md](TESTING.md)

## Signing และ notarization

ค่าเริ่มต้นของ `build_app.sh` เป็น ad-hoc signed และ **ยังไม่ได้ notarize**
หากมี Developer ID Application certificate ใน Keychain ให้กำหนด
`EDGE_CODESIGN_IDENTITY` เป็นชื่อ certificate ก่อนรันสคริปต์
สคริปต์จะใช้ hardened runtime และ timestamp

หากเตรียม notarytool Keychain profile ไว้แล้ว กำหนด `EDGE_NOTARY_PROFILE` เพิ่ม
สคริปต์จะส่ง ZIP ให้ Apple, รอผล, staple ticket, ตรวจ Gatekeeper และสร้าง ZIP ใหม่
อย่าใส่ private key, password หรือ certificate export ลง source repository

ชุดแจก 2.4.0 ครั้งนี้ส่งผ่านบัญชีที่ลงชื่อเข้าใช้ใน Xcode โดยสร้าง archive จาก Universal app
ที่เซ็น Developer ID แล้ว ใช้ `xcodebuild -exportArchive` แบบ `developer-id` / `upload`
จากนั้นส่งออกด้วย `xcodebuild -exportNotarizedApp` และตรวจ ticket กับ Gatekeeper
จึงไม่ได้สร้าง notarytool Keychain profile หรือเก็บ app-specific password เพิ่ม

รายละเอียดจาก [Apple Developer ID](https://developer.apple.com/developer-id/)

## ไฟล์สำหรับ GitHub Releases

- `Spartan-Build-Program-macOS-2.4.0.zip`: ตัวแอป
- `Spartan-Build-Program-macOS-2.4.0-with-guide.zip`: แอป คู่มือ และตัวอย่าง
- `SHA256SUMS.txt`: checksum ของ ZIP ทั้งสองไฟล์
- ใช้ข้อความจาก [release notes](RELEASE_NOTES_2.4.0.md)

แนบ ZIP ที่ build แล้วเป็น release assets แยกจาก source code ที่ GitHub สร้างให้
ตรวจ checksum ด้วย `shasum -a 256 -c SHA256SUMS.txt` จากโฟลเดอร์ที่มี ZIP ทั้งสองไฟล์
ดู [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

หากยังไม่ได้ทดสอบเครื่องอื่นหรือ hardware ให้ระบุขอบเขตนี้และใช้ pre-release
ใน release notes อย่าระบุว่า notarized เว้นแต่ขั้นตอน Apple ผ่านจริง
