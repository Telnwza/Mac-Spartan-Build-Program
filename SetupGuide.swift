import SwiftUI

struct SetupGuideView: View {
    let onBuild: () -> Void
    let onProgram: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Spartan Build & Program", systemImage: "cpu")
                        .font(.largeTitle.weight(.bold))
                    Text("Build VHDL • จัดการ Pin Mapping • Program บอร์ด บน macOS")
                        .foregroundStyle(.secondary)
                    Text("Build สำหรับ EDGE Spartan-7 · Program สำหรับ EDGE Spartan-7 และ Apex Surveyor-6")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("มีไฟล์ .bit แล้ว ใช้แอปกับ openFPGALoader ได้เลย")
                        Text("brew install openfpgaloader")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        HStack {
                            Link("ติดตั้ง Homebrew", destination: URL(string: "https://brew.sh")!)
                            Link("คู่มือ openFPGALoader", destination: URL(string: "https://trabucayre.github.io/openFPGALoader/guide/install.html#macos")!)
                            Spacer()
                            Button("ไปหน้า Program Board", action: onProgram)
                        }
                        Text("เลือกบอร์ดและไฟล์ให้ตรงกัน เริ่มทดสอบด้วย SRAM ซึ่งจะหายเมื่อปิดไฟ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                } label: {
                    Label("1. Program ไฟล์ .bit", systemImage: "arrow.down.to.line")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ติดตั้ง Docker Desktop แล้วเตรียม Vivado image ตามคู่มือ vivado-docker")
                        HStack {
                            Link("Docker Desktop สำหรับ Mac", destination: URL(string: "https://docs.docker.com/desktop/setup/install/mac-install/")!)
                            Link("เตรียม Vivado — vivado-docker", destination: URL(string: "https://github.com/filmil/vivado-docker")!)
                        }
                        Text("เลือก image แบบ linux/amd64 ที่ติดตั้ง Spartan-7 support สำหรับ xc7s15ftgb196-1 โปรแกรมไม่ได้รวม Vivado หรือ image มาให้")
                            .foregroundStyle(.secondary)
                        Text("ใน Local Build ตั้งชื่อ image และ Vivado setup ให้ตรงกับ image ของคุณ แล้วกดตรวจ Environment")
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                            GridRow { Text("Docker image"); Text(LocalBuildTemplates.defaultDockerImage) }
                            GridRow { Text("Vivado setup"); Text(LocalBuildTemplates.defaultVivadoSettingsPath) }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        Text("ชื่อ image เดิมที่ลงท้าย -rosetta ยังใช้ได้ กรอกชื่อตามที่ docker image ls แสดง")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("20 GiB เป็นขั้นต่ำสำหรับผลลัพธ์ Build ต้องเผื่อพื้นที่ Docker/Vivado image เพิ่มต่างหาก")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("ไปหน้า Local Build", action: onBuild)
                        }
                    }
                    .padding(8)
                } label: {
                    Label("2. Build จาก VHDL", systemImage: "hammer")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("เลือก VHDL → ตรวจ Top entity → กำหนด Pin Mapping หรือเลือก XDC → Build → Program")
                        Text("หลัง Build สำเร็จ แอปจะส่งไฟล์ไปหน้า Program Board ตรวจบอร์ดและโหมดก่อนเริ่มเขียนทุกครั้ง")
                            .foregroundStyle(.secondary)
                        Text("Intel และ Apple Silicon ใช้ตัวแอป Universal เดียวกัน ส่วน Docker และ Homebrew ต้องใช้ macOS รุ่นที่เครื่องมือเหล่านั้นรองรับ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                } label: {
                    Label("เริ่มงานแรก", systemImage: "list.number")
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
