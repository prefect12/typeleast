import SwiftUI

internal struct PermissionEducationModal: View {
    let onProceed: () -> Void
    let onCancel: () -> Void
    
    private var enableSmartPaste: Bool {
        TranscriptionSettingsStore.shared.isSmartPasteEnabled
    }

    private var isCN: Bool { L10n.isChinese }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "mic.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                if enableSmartPaste {
                    Image(systemName: "accessibility.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                }
            }
            .accessibilityLabel(isCN ? "需要权限" : "Permissions required")
            
            VStack(spacing: 12) {
                Text(enableSmartPaste
                    ? (isCN ? "需要权限" : "Permissions Required")
                    : (isCN ? "需要麦克风权限" : "Microphone Permission Required"))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(enableSmartPaste ? 
                     (isCN ? "Typeleast 需要以下权限才能正常工作：" : "Typeleast needs permissions to work properly:") :
                     (isCN ? "Typeleast 需要麦克风权限来录音：" : "Typeleast needs microphone access to record audio:"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label(isCN ? "麦克风权限用于录制音频" : "Microphone access to record audio", systemImage: "mic.circle.fill")
                        .foregroundStyle(.blue)
                    if enableSmartPaste {
                        Label(isCN ? "辅助功能权限用于粘贴转录文本" : "Accessibility access to paste transcribed text", systemImage: "accessibility.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Label(isCN ? "你的音频不会被永久保存" : "Your audio is never stored permanently", systemImage: "lock.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            
            HStack(spacing: 12) {
                Button(isCN ? "暂不" : "Not Now") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityHint(isCN ? "关闭此对话框且不授予权限" : "Dismiss this dialog without granting permissions")
                
                Button(enableSmartPaste
                    ? (isCN ? "允许权限" : "Allow Permissions")
                    : (isCN ? "允许麦克风权限" : "Allow Microphone Access")) {
                    onProceed()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(enableSmartPaste
                    ? (isCN ? "授予麦克风和辅助功能权限" : "Grant microphone and accessibility permissions")
                    : (isCN ? "授予麦克风权限" : "Grant microphone permission"))
            }
        }
        .padding(24)
        .frame(width: enableSmartPaste ? 420 : 400)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 20)
    }
}

internal struct PermissionRecoveryModal: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    private var isCN: Bool { L10n.isChinese }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(.orange)
                .accessibilityLabel(isCN ? "警告：权限未授权" : "Warning: Permissions denied")
            
            VStack(spacing: 12) {
                Text(isCN ? "需要权限" : "Permissions Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(isCN ? "Typeleast 需要麦克风和辅助功能权限才能正常工作。" : "Typeleast needs microphone and accessibility permissions to work properly.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text(isCN ? "点击下面的“打开系统设置”" : "Click 'Open System Settings' below")
                    }
                    
                    HStack {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text(isCN ? "在“麦克风”中启用 Typeleast" : "Enable Typeleast in 'Microphone' section")
                    }
                    
                    HStack {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text(isCN ? "在“辅助功能”中启用 Typeleast" : "Enable Typeleast in 'Accessibility' section")
                    }
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            
            HStack(spacing: 12) {
                Button(L10n.Common.cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityHint(isCN ? "关闭此对话框且不打开系统设置" : "Dismiss this dialog without opening System Settings")
                
                Button(L10n.SmartPastePermission.openSystemSettings) {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(isCN ? "打开 macOS 系统设置以启用权限" : "Open macOS System Settings to enable permissions")
            }
        }
        .padding(24)
        .frame(width: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 20)
    }
}
