import SwiftUI

extension View {
    /// Shared "Done" accessory above the keyboard for multi-line caption
    /// fields — with a vertical-axis TextField the Return key inserts
    /// newlines, so without this the keyboard has no way off the screen.
    func madKeyboardDoneButton(focus: FocusState<Bool>.Binding) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus.wrappedValue = false }
                    .fontWeight(.semibold)
            }
        }
    }
}
