# ติดตั้ง Spartan Build & Program for macOS

## เลือกสิ่งที่จะใช้

- มี `.bit` อยู่แล้ว: ติดตั้งแอปและ openFPGALoader
- ต้องการ Build VHDL: ติดตั้ง Docker Desktop และเตรียม Vivado image เพิ่ม

ตัวแอปใช้กับ Mac Apple Silicon และ Intel โดยตั้งเป้า macOS 13 ขึ้นไป
ตรวจ macOS ที่ Docker/Homebrew รุ่นที่คุณเลือกยังรองรับก่อนติดตั้งเครื่องมือเหล่านั้น

## เปิดแอปครั้งแรก

1. ดาวน์โหลด ZIP จาก Releases ของ repository นี้ แล้วแตกไฟล์
2. ลาก `Spartan Build & Program.app` ไป Applications แล้วเปิดแอป
3. หาก macOS บล็อกแอปที่ยังไม่ได้ notarize หลังลองเปิดแล้ว ให้เข้า
   **System Settings → Privacy & Security** ตรวจชื่อแอป แล้วเลือก **Open Anyway**
   เมื่อมั่นใจว่าเป็นไฟล์จากผู้เผยแพร่ที่คุณเชื่อถือ

ไม่ต้องปิด Gatekeeper ทั้งระบบ ดู [คำแนะนำจาก Apple](https://support.apple.com/en-us/102445)
ตรวจชนิด signature ของแต่ละชุดได้จาก release notes

## ติดตั้ง openFPGALoader

หากยังไม่มี Homebrew ให้ติดตั้งตาม [brew.sh](https://brew.sh) จากนั้นรัน:

```sh
brew install openfpgaloader
openFPGALoader --Version
```

ในแท็บ **Program Board** แอปจะแสดงตำแหน่ง openFPGALoader ที่พบ
หากติดตั้งไว้ที่อื่น กด **เลือก executable…** แล้วเลือกไฟล์ openFPGALoader
ใช้ **ค้นหาอัตโนมัติ** เพื่อกลับไปใช้ตำแหน่งมาตรฐาน หรือ **ตรวจอีกครั้ง** หลังติดตั้ง

## เตรียม Vivado สำหรับ Build

ติดตั้งและเปิด [Docker Desktop สำหรับ Mac](https://docs.docker.com/desktop/setup/install/mac-install/)
จากนั้นทำตามคู่มือของ [filmil/vivado-docker](https://github.com/filmil/vivado-docker)
สำหรับการดาวน์โหลด AMD installer และสร้าง image
ส่วนการเตรียม Vivado ใช้คู่มือต้นทางเป็นหลัก

สิ่งที่แอปเราต้องการจาก image:

| รายการ | ค่าที่ใช้ |
|---|---|
| Platform | `linux/amd64` |
| Vivado ที่ใช้เป็นค่าเริ่มต้น | 2025.2 |
| Device support | Spartan-7 ต้องพบ part `xc7s15ftgb196-1` |
| Image tag ตาม Makefile ของ upstream | `xilinx-vivado:2025.2` |
| Vivado setup ภายใน image | `/opt/Xilinx/2025.2/Vivado/settings64.sh` |

บน Apple Silicon ให้ใช้การตั้งค่า Rosetta/emulation ตามคู่มือต้นทาง
แอปจะใช้ `/opt/udev_stub.so` ของ upstream หากมีไฟล์นี้อยู่ใน image
image เดิมที่ไม่ได้มีไฟล์นี้จะเริ่มทำงานโดยไม่บังคับโหลดไฟล์ดังกล่าว
ชื่อ image และ Vivado setup เปลี่ยนได้ในแอป จึงไม่ต้อง rename image ให้ตรงกับค่าเริ่มต้น
ผู้ใช้เดิมที่มี `xilinx-vivado:2025.2-rosetta` สามารถใช้ค่านั้นต่อได้
ดู [ขอบเขตที่ทดสอบจริง](docs/TESTING.md) สำหรับสถานะความเข้ากันได้

ตรวจเครื่องมือก่อนเปิดหน้า Local Build:

```sh
docker info
docker image ls
```

## ตั้งค่า Local Build

1. ใส่ชื่อ image ให้ตรงกับ `docker image ls`
2. ใส่ path `settings64.sh` **ภายใน container**
3. เลือกโฟลเดอร์ผลลัพธ์ที่เขียนได้ จะเป็น internal drive หรือ external drive ก็ได้
4. เผื่อพื้นที่ผลลัพธ์อย่างน้อย 20 GiB และพื้นที่ Docker/Vivado image เพิ่มต่างหาก
5. กด **ตรวจ Environment** ต้องขึ้น **Local Vivado พร้อม Build**

แอปค้นหา Docker CLI จากตำแหน่งมาตรฐาน, `~/.docker/bin` และ PATH
หากติดตั้งนอกตำแหน่งเหล่านี้ สามารถใช้ `EDGE_PROGRAMMER_DOCKER_PATH` ตอนเปิด executable
ดูวิธีใน [เอกสารนักพัฒนา](docs/DEVELOPMENT.md)

## ทดลอง Build งานแรก

1. เลือก `examples/led_counter/led_counter.vhd`
2. เลือก Top entity `led_counter`
3. เลือกใช้ XDC เดิม แล้วเลือก `examples/led_counter/constraints.xdc`
4. กด **Build .bit บน Mac**
5. เมื่อ Timing, Routing และ header ผ่าน แอปจะส่งไฟล์ไปหน้า Program Board

ตัวอย่างนี้กำหนด pin สำหรับ EDGE Spartan-7 เท่านั้น
ตรวจรุ่นบอร์ดก่อนนำผลลัพธ์ไป Program

## Program บอร์ด

1. ต่อไฟและสาย USB/JTAG แล้วเลือกบอร์ดให้ถูกต้อง
2. เลือก `.bit` แล้วกด **ตรวจหาบอร์ด**
3. ใช้ **SRAM** สำหรับทดลองชั่วคราว หรือ **SPI Flash** สำหรับเก็บหลังปิดไฟ
4. กด Program และรอจนจบ ห้ามถอดสายหรือปิดไฟขณะเขียน Flash

หากต่อ FTDI หลายตัว ควรถอดอุปกรณ์ที่ไม่ใช้ก่อนตรวจบอร์ดครั้งแรก
การ Build ไม่จำเป็นต้องต่อบอร์ด และ container ไม่เข้าถึง USB/JTAG
