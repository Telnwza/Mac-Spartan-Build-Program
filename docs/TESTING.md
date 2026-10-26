# สถานะการตรวจรุ่น 2.4.0

ตรวจในเครื่องวันที่ 26 ตุลาคม 2026 (Asia/Bangkok)

## Environment ที่ตรวจจริง

- Mac Apple Silicon (`arm64`), macOS 27.0.1
- Apple Swift 6.4, target ของแอป macOS 13
- Python 3.14.8, openFPGALoader 1.1.1
- Vivado 2025.2 ใน Docker image `xilinx-vivado:2025.2-rosetta`
- Image ID แบบย่อ: `26e4929dd7ab` (`linux/amd64`)
- image ที่ทดสอบมี `/opt/udev_stub.so` และ setup path ค่าเริ่มต้น

ชื่อ tag เป็นชื่อของ image ที่มีอยู่ในเครื่องทดสอบ ไม่ใช่ข้อบังคับสำหรับเครื่องใหม่
ค่าเริ่มต้นการติดตั้งใหม่ใช้ `xilinx-vivado:2025.2` ตาม Makefile ของ
[filmil/vivado-docker](https://github.com/filmil/vivado-docker)
การอ้างอิง upstream ตรวจเมื่อวันที่ข้างต้น ไม่ใช่ผลการสร้าง image ใหม่จาก upstream

## ผ่านการตรวจแล้ว

| รายการ | ผล |
|---|---|
| workflow จำลอง | ผ่าน 30 กรณี |
| Universal app | compile `arm64` และ `x86_64`, รวมด้วย lipo |
| self-test ของแอป | ผ่านทั้ง arm64 และ x86_64 ผ่าน Rosetta บน Mac เครื่องเดียวกัน |
| codesign verify | ผ่านสำหรับ Developer ID Application พร้อม hardened runtime และ secure timestamp |
| Apple notarization | ผ่านและแนบ ticket แล้ว; stapler validate ผ่าน, Gatekeeper accepted เป็น Notarized Developer ID |
| Vivado cold run | ตรวจ Environment 11.76 วินาที, Build 72.1 วินาที |
| Vivado warm run | ใช้ cache เดิม, ตรวจ Environment 0.86 วินาที, Build 78.1 วินาที |
| ผลของ Build จริงทั้งสองรอบ | พบ `.bit`, Timing ผ่าน, routing error เป็นศูนย์, header ตรง Spartan-7 |
| UI บน Mac เครื่องนี้ | เปิดหน้าเริ่มต้น, ทางลัดสองหน้า, สถานะ loader และยกเลิก file chooser ได้ |
| เอกสาร | local links, plist, shell และ YAML syntax ผ่าน |
| ชุด source export | workflow 30 กรณีและ Universal build ผ่านจากชุดที่คัดสำหรับ GitHub |
| ZIP แอป | แตกไฟล์ใหม่แล้ว codesign verify และ self-test ทั้งสอง slice ผ่าน |

workflow จำลองครอบคลุมการเก็บค่าผู้ใช้เดิม, ค่าของการติดตั้งใหม่, tool discovery,
path ที่มีช่องว่าง/อัญประกาศ, Rosetta command, cache invalidation, พื้นที่ไม่พอ,
Docker/image/part check ที่ล้มเหลว, Build/Timing/Routing ที่ไม่ผ่าน และ cancellation
ใช้ synthetic bitstream header สำหรับจำลองเท่านั้น

เวลา Build ข้างต้นเป็นตัวอย่างวงจรเล็กสองรอบ ไม่ใช่ผล benchmark ของเครื่องอื่น
คำสั่งทดสอบซ้ำอยู่ใน [DEVELOPMENT.md](DEVELOPMENT.md)

## ยังไม่ได้ยืนยัน

- ติดตั้งและใช้งานบน Mac เครื่องอื่นหรือ macOS 13
- การทำงานบน Intel Mac จริง (การมี slice x86_64 ไม่ใช่ผลทดสอบ hardware)
- สร้าง Vivado image จาก AMD installer ใหม่ตาม upstream ปัจจุบันตั้งแต่ศูนย์
- Detect/Program SRAM/เขียนและล้าง SPI Flash บนบอร์ดจริงสำหรับรุ่นนี้
- การแจ้งเตือนของรุ่นนี้แบบ end-to-end บนเครื่องปลายทาง
- GitHub Actions: เตรียม workflow แล้ว แต่ยังไม่ได้รันบน GitHub
- ประสบการณ์ดาวน์โหลดและเปิด ZIP ผ่านอินเทอร์เน็ตบน Mac เครื่องปลายทาง

ใช้ชุดนี้เป็น pre-release สำหรับทดสอบกับผู้ใช้กลุ่มแรก แล้วเพิ่มผลเครื่องปลายทางก่อน
ประกาศขอบเขตการรองรับที่กว้างขึ้น
