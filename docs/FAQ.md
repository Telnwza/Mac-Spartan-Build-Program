# คำถามและปัญหาที่พบบ่อย

## ต้องติดตั้ง Vivado ทุกคนไหม

หากมี `.bit` และต้องการ Program บอร์ด ใช้แอปกับ openFPGALoader ได้เลย
Docker และ Vivado ใช้เฉพาะการ Build จาก VHDL

## ไม่พบ openFPGALoader

รัน `brew install openfpgaloader` แล้วกด **ตรวจอีกครั้ง** ในหน้า Program Board
หากติดตั้งไว้ที่อื่น ใช้ **เลือก executable…**
ถ้าเลือก path ผิด แอปจะแสดงว่าเปิดไม่ได้ ให้เลือกใหม่หรือกด **ค้นหาอัตโนมัติ**

## ไม่พบ Docker หรือ Engine ไม่พร้อม

ติดตั้งและเปิด Docker Desktop รอให้ Engine ทำงาน แล้วกด **ตรวจ Environment**
ดูว่า `docker info` ทำงานใน Terminal ได้หรือไม่

## ไม่พบ image ทั้งที่ติดตั้ง Vivado แล้ว

ดู `docker image ls` แล้วกรอกชื่อและ tag ให้ตรงกัน
ค่าเริ่มต้นคือ `xilinx-vivado:2025.2` แต่ image เดิมของคุณอาจลงท้าย `-rosetta`
แอปใช้ image ภายใน Docker context ของเครื่อง ไม่ดาวน์โหลด image อัตโนมัติ

## ไม่พบ settings64.sh หรือ FPGA part

Vivado setup ต้องเป็น path ภายใน image ไม่ใช่ path บน Mac
ตรวจว่า image ติดตั้ง Spartan-7 support และมี part `xc7s15ftgb196-1`
ดู [วิธีเตรียม image](https://github.com/filmil/vivado-docker)

## Vivado ล้มบน Apple Silicon

ตรวจ Rosetta/emulation และ image ตามหัวข้อ
[Apple Silicon / Rosetta Support](https://github.com/filmil/vivado-docker#apple-silicon--rosetta-support)
แอปจะโหลด udev stub เมื่อมีไฟล์นั้นใน image และใช้ Tcl แบบ in-process
หลังเปลี่ยน image ให้กด **ตรวจ Environment** ใหม่

## ทำไม Build ผ่านแล้วไม่ได้ไฟล์ไป Program

แอปต้องตรวจพบ bitstream ที่ตรงบอร์ด, `BUILD_COMPLETE`, Timing ผ่าน และ routing error
เป็นศูนย์ด้วย เปิด `build.log`, `timing_summary.rpt` และ `route_status.rpt` ในโฟลเดอร์ผลลัพธ์
อย่าข้ามผลตรวจด้วยการเปลี่ยนนามสกุลหรือแก้ header

## ต้องใช้ External SSD ชื่อเดียวกับผู้พัฒนาไหม

เลือกโฟลเดอร์ผลลัพธ์ของคุณเองได้ แอปไม่ได้ผูกกับชื่อ volume หรือ Docker.raw
พื้นที่ Docker image จัดการผ่าน Docker Desktop แยกจากโฟลเดอร์ผลลัพธ์

## Build ให้ Apex Surveyor-6 ได้ไหม

Local Build และ Pin Mapping ในรุ่นนี้ใช้ EDGE Spartan-7 เท่านั้น
หน้า Program รองรับ Apex Surveyor-6 เมื่อมี `.bit` ที่สร้างสำหรับบอร์ดนั้นอยู่แล้ว

## ใช้ Windows/Linux ได้ไหม

ตัว GUI ใช้ SwiftUI/AppKit สำหรับ macOS เท่านั้น
Universal Binary หมายถึง Apple Silicon และ Intel Mac

## แจ้งปัญหาอย่างไร

เปิด [Issues](https://github.com/Telnwza/Mac-Spartan-Build-Program/issues/new/choose) พร้อมรุ่นแอป, macOS, CPU, ชื่อบอร์ด, ขั้นตอนที่ทำ
และ log ช่วงที่เกิดปัญหา หากเป็นปัญหา Build ให้ระบุ image tag และ Vivado setup path ด้วย
ตรวจข้อมูลส่วนตัวหรือ credentials ใน log ก่อนแนบ
