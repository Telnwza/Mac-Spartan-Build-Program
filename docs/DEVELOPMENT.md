# พัฒนาและ Build ตัวแอป

ต้องมี Xcode ที่เลือกใช้งานผ่าน `xcode-select` หรือ `DEVELOPER_DIR` และ Python 3
ตัวแอปใช้ SwiftUI/AppKit และ system frameworks ไม่มีแพ็กเกจ Swift ภายนอก

```sh
xcode-select -p
xcrun swiftc --version
python3 --version
zsh build_app.sh
```

สคริปต์สร้าง `arm64` และ `x86_64` รวมด้วย `lipo` รัน self-test และตรวจ codesign
ผลลัพธ์อยู่ใน `dist/builds/<timestamp>/` จะหยุดหากโฟลเดอร์ปลายทางมีอยู่แล้ว
ไม่ต้องมี Docker/Vivado หรือบอร์ดเพื่อ build ตัวแอปและรัน self-test

## ตรวจ workflow แบบจำลอง

```sh
zsh diagnostics/check_build_workflow.sh
```

ตรวจการติดตั้งใหม่, ค่าที่บันทึกไว้, tool discovery, shell quoting, cache,
การเปลี่ยน image/engine/setup, พื้นที่ไม่พอ, Docker ใช้ไม่ได้, Build/Timing/Routing ล้มเหลว
และ cancellation ใช้ defaults แยกจากแอปจริง และไม่เรียก Docker
bitstream ในการทดสอบนี้เป็น synthetic header ใช้ทดสอบ flow เท่านั้น

## ตรวจด้วย Vivado จริง

เมื่อเตรียม image แล้ว รัน:

```sh
EDGE_LOCAL_TEST_DOCKER_IMAGE=xilinx-vivado:2025.2 \
  zsh diagnostics/check_build_workflow.sh live
```

หาก setup อยู่ตำแหน่งอื่น กำหนด `EDGE_LOCAL_TEST_VIVADO_SETTINGS` เพิ่ม
สคริปต์ Build สองครั้งเพื่อตรวจ cold/warm cache ใช้ตัวอย่างใน diagnostics
ไม่ส่งผลลัพธ์ไป Program บอร์ด พิมพ์ตำแหน่งหลักฐานที่ `TEST_ROOT`

## โครงสร้าง source

- `EdgeProgrammer.swift`: app, Program Board, tool discovery และ bitstream inspection
- `SetupGuide.swift`: หน้าเริ่มต้นใช้งานและลิงก์เครื่องมือ
- `LocalBuild.swift`: environment, Docker workflow, mapping UI และผลตรวจ Build
- `VHDLSupport.swift`, `PinMappingSupport.swift`: อ่าน VHDL และจัดการ mapping
- `LogSupport.swift`, `BuildNotifications.swift`: log และแจ้งเตือน
- `edge-spartan7.json`: board profile ที่บรรจุใน app bundle

ชื่อ executable `EdgeProgrammer`, bundle ID และ preference keys เดิมยังคงไว้
เพื่อให้ผู้ใช้รุ่นก่อนเปิดไฟล์และใช้ค่าที่บันทึกไว้ต่อได้
การเปลี่ยนวิธีเริ่ม Vivado ใช้ cache key ใหม่เพื่อให้ตรวจ Environment เต็มอีกครั้ง

หาก tool อยู่ path พิเศษ ให้เปิด executable พร้อม `EDGE_PROGRAMMER_DOCKER_PATH`
หรือ `EDGE_PROGRAMMER_LOADER_PATH` ซึ่งต้องชี้ไปไฟล์ executable
ใน Finder ให้ใช้ปุ่มเลือก executable สำหรับ openFPGALoader ได้โดยตรง

## GitHub Actions

workflow ใน `.github/workflows/ci.yml` เตรียมไว้สำหรับ macOS ARM และ Intel
ตรวจ fake workflow แล้ว build Universal app โดยไม่ใช้ Vivado, hardware หรือ signing secrets
ผลบน GitHub ต้องดูจาก Actions หลังอัปโหลด source; การตรวจในเครื่องไม่ใช่ผล CI
