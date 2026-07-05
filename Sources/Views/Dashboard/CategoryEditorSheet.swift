import SwiftUI

internal struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categoryStore: CategoryStore
    let originalCategory: CategoryDefinition?
    let onSave: (CategoryDefinition) -> Void
    let onDelete: (() -> Void)?

    @State private var displayName: String
    @State private var identifier: String
    @State private var icon: String
    @State private var accentColor: Color
    @State private var promptDescription: String
    @State private var promptTemplate: String
    @State private var validationError: String?

    private let isNewCategory: Bool
    private let isSystem: Bool

    init(
        category: CategoryDefinition?,
        categoryStore: CategoryStore = .shared,
        onSave: @escaping (CategoryDefinition) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.categoryStore = categoryStore
        self.originalCategory = category
        self.onSave = onSave
        self.onDelete = onDelete
        self.isNewCategory = category == nil
        self.isSystem = category?.isSystem ?? false

        let cat = category ?? CategoryDefinition(
            id: "new-category",
            displayName: L10n.Categories.newCategoryDefaultName,
            icon: "sparkles",
            colorHex: "#888888",
            promptDescription: L10n.Categories.categoryPurposePlaceholder,
            promptTemplate: CategoryDefinition.fallback.promptTemplate,
            isSystem: false
        )

        _displayName = State(initialValue: cat.localizedDisplayName)
        _identifier = State(initialValue: cat.id)
        _icon = State(initialValue: cat.icon)
        _accentColor = State(initialValue: cat.color)
        _promptDescription = State(initialValue: cat.localizedPromptDescription)
        _promptTemplate = State(initialValue: cat.promptTemplate)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: icon.isEmpty ? "questionmark" : icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName.isEmpty ? L10n.Categories.categoryNamePlaceholder : displayName)
                            .font(.headline)
                            .lineLimit(1)

                        Text(identifier.isEmpty ? L10n.Categories.identifierPlaceholder : identifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 0)

                    if isSystem {
                        Text(L10n.Categories.systemBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L10n.Categories.identity) {
                TextField(L10n.Categories.displayName, text: $displayName)

                TextField(L10n.Categories.identifier, text: $identifier)
                    .disabled(isSystem)

                if isSystem {
                    Text(L10n.Categories.systemIdentifierHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.Categories.appearance) {
                TextField(L10n.Categories.icon, text: $icon)

                ColorPicker(L10n.Categories.color, selection: $accentColor, supportsOpacity: false)
            }

            Section(L10n.Categories.correction) {
                TextField(L10n.Categories.description, text: $promptDescription, axis: .vertical)
                    .lineLimit(2...3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.Categories.promptTemplate)
                        .font(.subheadline.weight(.semibold))

                    TextEditor(text: $promptTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )

                    Text(L10n.Categories.promptTemplateHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }

            if !isNewCategory && !isSystem, let onDelete {
                Section {
                    Button(L10n.Categories.deleteCategory, role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNewCategory ? L10n.Categories.newCategoryTitle : L10n.Categories.editCategoryTitle)
        .frame(width: 560, height: 680)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.Common.cancel, role: .cancel) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isNewCategory ? L10n.Common.add : L10n.Common.save) {
                    save()
                }
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        validationError = nil

        let trimmedId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            validationError = L10n.Categories.displayNameRequired
            return
        }

        // Check for duplicate ID (only if ID changed or new category).
        let originalId = originalCategory?.id
        if trimmedId != originalId && categoryStore.containsCategory(withId: trimmedId) {
            validationError = L10n.Categories.duplicateIdentifier
            return
        }

        let category = CategoryDefinition(
            id: isSystem ? (originalCategory?.id ?? trimmedId) : trimmedId,
            displayName: trimmedName,
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: accentColor.hexString() ?? "#888888",
            promptDescription: promptDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTemplate: promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            isSystem: isSystem
        )

        onSave(category)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CategoryEditorSheet(category: CategoryDefinition.fallback, onSave: { _ in })
    }
}
