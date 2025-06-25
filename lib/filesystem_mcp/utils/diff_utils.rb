# frozen_string_literal: true

module FileSystemMCP
  module Utils
    module DiffUtils
      def create_unified_diff(old_content, new_content, file_path)
        if old_content == new_content
          "No changes detected.\n"
        else
          old_lines = old_content.lines.size
          new_lines = new_content.lines.size
          "--- a/#{file_path}\n+++ b/#{file_path}\n@@ -1,#{old_lines} +1,#{new_lines} @@\n" +
          "Content changed (#{old_lines} -> #{new_lines} lines)\n"
        end
      end
    end
  end
end