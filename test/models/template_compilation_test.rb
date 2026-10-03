# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Every template must compile, checked the way Rails compiles it.
#
# Two failures this catches that nothing else does, both invisible in a diff and
# both fatal only at request time:
#
#   * a mangled keyword argument — `class:` written to disk as `class=`;
#   * a block inside `<%= %>` whose output the engine cannot capture.
#
# Compiling with stdlib `ERB` or a bare `RubyVM` compile is not a substitute: ERB
# cannot compile a captured block at all, and a compiled template body uses `yield`,
# which is only valid inside a method. So this uses Rails' own handler and wraps the
# compiled body in a method, as ActionView does.
class TemplateCompilationTest < ActiveSupport::TestCase
  test "every template compiles" do
    handler = ActionView::Template::Handlers::ERB
    broken = []

    Dir[Rails.root.join("app/views/**/*.erb")].sort.each do |path|
      name = path.sub("#{Rails.root}/", "")
      begin
        body = handler.new.call(OpenStruct.new(options: { escape: true }), File.read(path))
        RubyVM::InstructionSequence.compile("def _render; #{body}; end", name)
      rescue SyntaxError => error
        broken << "#{name}: #{error.message.lines.first(6).join(' ')}"
      end
    end

    assert_empty broken, "templates that do not compile:\n#{broken.join("\n")}"
  end
end
