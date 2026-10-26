# Spartan Build & Program for macOS 2.4.0

เปลี่ยนชื่อจาก FPGA Spartan Programmer เพื่อสื่อถึงทั้ง Build, Pin Mapping และ Program

## เปลี่ยนแปลง

- เพิ่มหน้าเริ่มต้นใช้งานพร้อมลิงก์ติดตั้งเครื่องมือและทางลัดไปแต่ละ workflow
- การติดตั้งใหม่ใช้ชื่อ image มาตรฐานของ vivado-docker: `xilinx-vivado:2025.2`
- เก็บ image tag และค่า Environment ของผู้ใช้เดิมไว้
- บน Apple Silicon ใช้ udev stub ของ upstream เมื่อ image มีไฟล์นี้ ทั้งตอนตรวจ Environment และ Build
- แสดงสถานะและเลือก openFPGALoader executable ได้จากหน้า Program Board
- ค้นหาเครื่องมือผ่าน PATH เพิ่มจากตำแหน่งมาตรฐาน
- Build source ด้วย Xcode ที่เลือกไว้ได้ เพิ่มชุด source export, CI และคู่มือ

## ขอบเขต

- Local Build / Pin Mapping: EDGE Spartan-7 `xc7s15ftgb196-1`
- Program: EDGE Spartan-7 และ Apex Surveyor-6
- GUI: macOS เท่านั้น; Universal Binary สำหรับ Apple Silicon และ Intel
- ต้องติดตั้งเครื่องมือภายนอกแยก ดู [คู่มือติดตั้ง](https://github.com/Telnwza/Mac-Spartan-Build-Program/blob/v2.4.0/INSTALL_MANUAL_TH.md)

## สถานะชุดเตรียมเผยแพร่

ชุดแจกผ่าน **Developer ID signing และ Apple notarization** แล้วเมื่อวันที่ 26 ตุลาคม 2026
แนบ ticket กับตัวแอปเรียบร้อย ตรวจ `stapler validate`, `codesign --verify` และ
Gatekeeper ได้ผล `accepted` พร้อม `source=Notarized Developer ID`
ชุดนี้ส่งผ่านบัญชีที่ลงชื่อเข้าใช้ใน Xcode
ดู [ผลทดสอบและส่วนที่ยังไม่ยืนยัน](https://github.com/Telnwza/Mac-Spartan-Build-Program/blob/v2.4.0/docs/TESTING.md) ก่อนใช้งาน
ผลทดสอบบน Mac เครื่องอื่นและการ Program hardware ต้องบันทึกแยกจาก self-test
