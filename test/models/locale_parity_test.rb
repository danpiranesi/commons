require "test_helper"

# The Danish and English files must describe the same app. A missing section
# or a duplicated key fails silently until somebody hits "translation missing".
class LocaleParityTest < ActiveSupport::TestCase
  LOCALE_FILES = {
    "da" => Rails.root.join("config/locales/da.yml"),
    "en" => Rails.root.join("config/locales/en.yml")
  }.freeze

  def tree(locale)
    YAML.load_file(LOCALE_FILES.fetch(locale)).fetch(locale)
  end

  def leaf_keys(node, prefix = [])
    node.flat_map do |key, value|
      value.is_a?(Hash) ? leaf_keys(value, prefix + [key]) : [(prefix + [key]).join(".")]
    end
  end

  test "every English string has a Danish one" do
    missing = leaf_keys(tree("en")) - leaf_keys(tree("da"))
    assert_empty missing, "untranslated in da.yml:\n  #{missing.join("\n  ")}"
  end

  test "no locale file defines the same key twice" do
    LOCALE_FILES.each do |locale, path|
      seen = Hash.new(0)
      stack = []
      File.readlines(path, encoding: "UTF-8").each_with_index do |raw, index|
        match = raw.match(/\A(\s*)([A-Za-z0-9_]+):\s*(.*)\z/)
        next unless match

        depth = match[1].length / 2
        stack = stack[0, depth].to_a
        stack[depth] = match[2]
        path_key = stack.compact.join(".")
        seen[path_key] += 1
        assert_equal 1, seen[path_key],
                     "#{locale}.yml:#{index + 1} defines #{path_key} twice — the later one wins silently"
      end
    end
  end
end
