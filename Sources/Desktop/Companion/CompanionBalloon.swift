import SwiftUI
import AppKit

/// The yellow Office 97 balloon: a rounded box with a tail towards the character, Tahoma, blue
/// bullets for choices and little grey buttons.
struct CompanionBalloonView: View {
    @ObservedObject var model: CompanionController
    @State private var newTodo = ""

    static let paper = Color(red: 1, green: 1, blue: 0.8)
    static let bullet = Color(red: 0, green: 0, blue: 0.75)
    static let link = Color(red: 0, green: 0, blue: 0.8)
    static func font(_ size: CGFloat = 12, bold: Bool = false) -> Font {
        Font.custom(bold ? "Tahoma Bold" : "Tahoma", size: size)
    }
    private static let tail: CGFloat = 14

    var body: some View {
        content
            .font(Self.font())
            .foregroundColor(.black)
            .padding(10)
            .frame(width: CompanionController.balloonWidth - 2, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(BalloonShape(tailUp: model.tailUp, tailX: model.tailX, tail: Self.tail)
                .fill(Self.paper)
                .overlay(BalloonShape(tailUp: model.tailUp, tailX: model.tailX, tail: Self.tail).stroke(Color.black, lineWidth: 1))
                .padding(model.tailUp ? .top : .bottom, -Self.tail))
            .padding(model.tailUp ? .top : .bottom, Self.tail)
            .padding(1)
            .background(GeometryReader { g in
                Color.clear.onChange(of: g.size) { _, _ in model.positionBalloon() }
            })
            .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .none:
            EmptyView()
        case .message(let m):
            VStack(alignment: .leading, spacing: 8) {
                Text(m.text).fixedSize(horizontal: false, vertical: true)
                if !m.buttons.isEmpty {
                    buttons(m.buttons.map { b in (b.0, { b.1(); model.closeBalloon() }) })
                }
            }
        case .home:
            VStack(alignment: .leading, spacing: 6) {
                Text("What would you like to do?").font(Self.font(bold: true))
                choice("Clipboard history") { model.open(.clipboard) }
                choice("Note and to-dos") { model.open(.notes) }
                choice("Today's meetings and reminders") { model.showAgenda() }
                choice("Wikipedia: today's featured article") { model.showWikipedia() }
                buttons([("Options", { model.closeBalloon(); AppDelegate.shared?.showSettings(tab: .desktop) }),
                         ("Close", { model.closeBalloon() })])
            }
        case .clipboard:
            clipboardPage
        case .notes:
            notesPage
        case .agenda(let items):
            agendaPage(items)
        }
    }

    // MARK: Pages

    @ViewBuilder private var clipboardPage: some View {
        let items = model.clipboard.items
        VStack(alignment: .leading, spacing: 6) {
            Text("Clipboard history").font(Self.font(bold: true))
            if !AppSettings.shared.companion.clipboard {
                Text("The clipboard history is switched off in Settings ▸ Desktop.")
            } else if model.clipboard.denied {
                Text("macOS does not let RetroMac read the clipboard. Allow it under Privacy & Security ▸ Paste from Other Apps.")
                    .fixedSize(horizontal: false, vertical: true)
            } else if items.isEmpty {
                Text("Nothing yet. Copy some text and I'll keep the last ten here, until RetroMac quits.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Click one to copy it again.").font(Self.font(11))
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                    choice(Self.preview(s)) {
                        model.clipboard.copy(s)
                        model.closeBalloon()
                    }
                    .help(s.prefix(500))
                }
            }
            buttons([("Back", { model.open(.home) }), ("Close", { model.closeBalloon() })])
        }
    }

    static func preview(_ s: String) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 70 ? String(flat.prefix(70)) + "…" : flat
    }

    @ViewBuilder private var notesPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note").font(Self.font(bold: true))
            TextEditor(text: $model.notes.note)
                .font(Self.font())
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .frame(height: 64)
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .accessibilityLabel("Note")
            Text("To-dos").font(Self.font(bold: true))
            ForEach($model.notes.todos) { $todo in
                HStack(spacing: 6) {
                    Toggle(isOn: $todo.done) {
                        Text(todo.text).strikethrough(todo.done)
                    }
                    .toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                    Button {
                        model.notes.todos.removeAll { $0.id == todo.id }
                    } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(todo.text)")
                }
            }
            TextField("New to-do, then Return", text: $newTodo)
                .textFieldStyle(.plain)
                .padding(3)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .onSubmit {
                    let t = newTodo.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    model.notes.todos.append(.init(text: t))
                    newTodo = ""
                }
            buttons([("Clear done", { model.notes.todos.removeAll(where: \.done) }),
                     ("Back", { model.open(.home) }), ("Close", { model.closeBalloon() })])
        }
        .onAppear { model.makeBalloonKey() }
    }

    @ViewBuilder private func agendaPage(_ items: [CompanionCalendar.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(Self.font(bold: true))
            if items.isEmpty {
                Text("Nothing more today. Enjoy!")
            }
            ForEach(items) { item in
                HStack(spacing: 6) {
                    if item.reminder != nil {
                        Button {
                            model.calendar.complete(item)
                            model.showAgenda()
                        } label: { Image(systemName: "square") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark \(item.title) as done")
                        Text(item.title)
                    } else {
                        Text(item.start.map { $0.formatted(date: .omitted, time: .shortened) } ?? "").font(Self.font(bold: true))
                        Text(item.title)
                        if let link = item.link {
                            Spacer(minLength: 0)
                            smallButton("Join") { NSWorkspace.shared.open(link); model.closeBalloon() }
                        }
                    }
                }
            }
            buttons([("Back", { model.open(.home) }), ("Close", { model.closeBalloon() })])
        }
    }

    // MARK: Pieces

    private func choice(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(Self.bullet).frame(width: 7, height: 7)
                // Underlined in link blue, so it reads as something to click.
                Text(title).underline().foregroundColor(Self.link)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    private func buttons(_ list: [(String, () -> Void)]) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(Array(list.enumerated()), id: \.offset) { _, b in smallButton(b.0, b.1) }
        }
        .padding(.top, 2)
    }

    private func smallButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Self.font(11))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color(white: 0.85))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Rounded box plus a tail at `tailX`, below the box or (tailUp) above it.
struct BalloonShape: Shape {
    var tailUp: Bool
    var tailX: CGFloat
    var tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.divided(atDistance: tail, from: tailUp ? .minYEdge : .maxYEdge).remainder
        let p = Path(roundedRect: box, cornerRadius: 8)
        let x = min(max(tailX, box.minX + 14), box.maxX - 14)
        var t = Path()
        if tailUp {
            t.move(to: CGPoint(x: x - 8, y: box.minY + 1))
            t.addLine(to: CGPoint(x: x + 4, y: rect.minY))
            t.addLine(to: CGPoint(x: x + 6, y: box.minY + 1))
        } else {
            t.move(to: CGPoint(x: x - 8, y: box.maxY - 1))
            t.addLine(to: CGPoint(x: x + 4, y: rect.maxY))
            t.addLine(to: CGPoint(x: x + 6, y: box.maxY - 1))
        }
        t.closeSubpath()
        return p.union(t)   // one outline, so the stroke does not cross the tail's root
    }
}
