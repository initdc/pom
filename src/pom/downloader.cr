require "http"
require "file_utils"
require "progress"

class Downloader
  property url : String
  property output : String
  property connections : Int32
  property chunk_size : Int64

  def initialize(@url, @output, @connections = 4, @chunk_size = 1024_i64 * 1024)
    @temp_dir = "pom_downloader_temp_#{@output}"
    @file_size = 0_i64
    @ranges = [] of Range(Int64, Int64)
  end

  def start
    # 创建临时目录
    FileUtils.mkdir_p(@temp_dir)

    # 获取文件大小和支持范围请求
    head_response = HTTP::Client.head(@url)
    if head_response.status_code >= 300 && head_response.status_code < 400
      location = head_response.headers["Location"]?
      if location
        @url = location
        head_response = HTTP::Client.head(@url)
      end
    elsif !head_response.success?
      raise "无法访问URL: #{@url}"
    end

    @file_size = head_response.headers["Content-Length"]?.try(&.to_i64) || 0_i64
    supports_ranges = head_response.headers["Accept-Ranges"]? == "bytes"

    if !supports_ranges
      puts "服务器不支持范围请求，使用单线程下载"
      single_thread_download
      return
    end

    # 检查是否已有部分下载
    check_existing_downloads

    # 创建下载范围
    create_download_ranges

    # 开始多线程下载
    download_chunks

    # 合并文件
    merge_files
  end

  private def check_existing_downloads
    if File.exists?(@output)
      puts "文件已存在完整版本"
      exit
    end

    # 检查临时文件
    existing_chunks = Dir.children(@temp_dir).map { |f| f.to_i64 }.sort!
    return if existing_chunks.empty?

    # 获取已下载的大小
    downloaded = existing_chunks.sum do |i|
      File.size("#{@temp_dir}/#{i}")
    end

    puts "发现已下载部分: #{downloaded} / #{@file_size} bytes"
  end

  private def create_download_ranges
    chunk_size = (@file_size / @connections).to_i64
    start = 0_i64

    while start < @file_size
      ending = Math.min(start + chunk_size - 1, @file_size - 1)
      @ranges << (start..ending)
      start = ending + 1
    end
  end

  private def download_chunks
    progress = Progress.new(width: 100, total: @file_size)

    channel = Channel(Nil).new

    @ranges.each_with_index do |range, index|
      spawn do
        download_chunk(range, index, progress)
        channel.send(nil)
      end
    end

    @ranges.size.times { channel.receive }
    progress.set(@file_size)
  end

  private def download_chunk(range : Range(Int64, Int64), index : Int32, progress)
    temp_file = "#{@temp_dir}/#{index}"
    start_pos = 0_i64

    # 如果文件已存在，获取已下载的位置
    if File.exists?(temp_file)
      start_pos = File.size(temp_file)
    end

    # 如果已经下载完成，跳过
    if start_pos >= range.size
      return
    end

    # 创建HTTP请求
    headers = HTTP::Headers{
      "Range" => "bytes=#{range.begin + start_pos}-#{range.end}",
    }

    HTTP::Client.get(@url, headers) do |response|
      if !response.success?
        raise "下载块 #{index} 失败: #{response.status_code}"
      end

      if (body_io = response.body_io?)
        File.open(temp_file, "a") do |file|
          size = IO.copy(body_io, file)
          progress.tick(size)
        end
      else
        raise "body_io is nil"
      end
    end
  end

  private def merge_files
    puts "\n正在合并文件..."
    File.open(@output, "w") do |output_file|
      @ranges.size.times do |i|
        temp_file = "#{@temp_dir}/#{i}"
        File.open(temp_file) do |input_file|
          IO.copy(input_file, output_file)
        end
      end
    end

    # 清理临时文件
    FileUtils.rm_rf(@temp_dir)
    puts "下载完成: #{@output}"
  end

  private def single_thread_download
    progress = Progress.new(width: 100, total: @file_size)

    HTTP::Client.get(@url) do |response|
      if !response.success?
        raise "下载失败: #{response.status_code}"
      end

      if (body_io = response.body_io?)
        File.open(@output, "a") do |file|
          size = IO.copy(body_io, file)
          progress.tick(size)
        end
      else
        raise "body_io is nil"
      end
    end

    progress.set(100)
    puts "\n下载完成: #{@output}"
  end
end

# 使用示例
begin
  if ARGV.size < 2
    puts "使用方法: crystal downloader.cr <URL> <输出文件> [连接数]"
    exit 1
  end

  url = ARGV[0]
  output = ARGV[1]
  connections = ARGV[2]?.try(&.to_i) || 4

  downloader = Downloader.new(url, output, connections)
  downloader.start
rescue ex
  puts "错误: #{ex.message}"
  exit 1
end
