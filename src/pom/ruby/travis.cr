require "xml"

module Pom
  module Ruby
    module Travis
      HTML = "#{__DIR__}/data/rubies.travis-ci.org.html"

      def self.rubies
        doc = XML.parse_html(File.read(HTML))

        doc.xpath_nodes("//div[@class='os_arch'] //ul //li //a").group_by do |link|
          sp_arr = link["href"].split("/")

          ver = sp_arr[-1]
          arch = sp_arr[-2]
          os_ver = sp_arr[-3]
          os = sp_arr[-4]

          "#{os} #{os_ver} (#{arch})"
        end
      end

      def self.print_rubies
        rubies().each do |os_arch, links|
          puts "#{os_arch}:"
          links.each do |link|
            puts "  #{link["href"]}.tar.bz2"
          end
        end
      end
    end
  end
end
