import SwiftUI

/// TODO: LoRA/QLoRA fine-tuning (ported from fine_tune.py) isn't wired
/// up yet - it needs an MLX Swift training loop (forward/backward pass +
/// optimizer over a LoRA-adapted model), which is a meaningfully separate
/// chunk of work from the inference path. This screen is left in place
/// with the Liquid Glass shell so the tab isn't just missing, and so the
/// form fields are ready once the training code lands.
struct TuningView: View {
    @Environment(AppSettings.self) private var settings

    @State private var datasetPath = ""
    @State private var outputDir = ""
    @State private var baseModel = ""

    var body: some View {
        let lang = settings.languageCode

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassHeader(title: Loc.t("tuning_header", lang: lang), subtitle: Loc.t("tuning_note", lang: lang))

                GlassCard {
                    LabeledContent("Dataset") {
                        TextField("dataset.jsonl", text: $datasetPath).textFieldStyle(.plain)
                    }
                    LabeledContent("Output folder") {
                        TextField("~/LocAI_tuning_output", text: $outputDir).textFieldStyle(.plain)
                    }
                    LabeledContent("Base model") {
                        TextField("mlx-community/…", text: $baseModel).textFieldStyle(.plain)
                    }
                }

                GlassCard {
                    GlassActionButton(title: "Start tuning", systemImage: "wand.and.stars", prominent: true, isDisabled: true) {}
                    Text("Not implemented yet in the Swift port.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}
