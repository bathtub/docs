require 'fileutils'
require 'json'
require 'open-uri'

module Downloads
  # repositories returns a list of all repositories with releases.
  def self.repositories
    @_repositories ||= begin
      repos = Dir.glob('downloads/*').map { |dir| Repository.new(dir) }
      repos.sort_by { |r| r.name }
    end
  end

  # operating_systems returns a list of all operating systems downloads can be
  # provided for.
  def self.operating_systems
    repositories.inject([]) do |list, repo|
      list += repo.releases.map { |r| r.binaries.map(&:os) }.flatten
    end.uniq.sort
  end

  # architectures returns a list of all architectures downloads can be
  # provided for.
  def self.architectures
    repositories.inject([]) do |list, repo|
      list += repo.releases.map { |r| r.binaries.map(&:arch) }.flatten
    end.uniq.sort
  end

  # checksum returns the checksum for a given filename of a given release. It
  # might try to download the sha256sums.txt from the given release if available
  # and not already cached.
  def self.checksum(release, name)
    @_checksums ||= {}
    @_checksums[release.id] ||= begin
      asset = release.assets.find { |a| a['name'] == 'sha256sums.txt' }

      if asset
        cache = ['downloads', '.cache', release.id, 'sha256sums.txt'].join('/')
        unless File.exists?(cache)
          FileUtils.mkdir_p(File.dirname(cache))
          File.open(cache, 'wb') do |file|
            file.write(URI.parse(asset['browser_download_url']).read)
          end
        end

        File.readlines(cache).each_with_object({}) do |line, memo|
          checksum, filename = line.split(/\s+/)
          memo[filename] = checksum
        end
      else
        {}
      end
    end
    @_checksums[release.id][name]
  end

  class Repository
    def initialize(dir)
      @repo = JSON.parse(File.read(File.join(dir, 'repo.json')))
      @releases = JSON.parse(File.read(File.join(dir, 'releases.json')))
    end

    def name
      @repo['name']
    end

    def full_name
      @repo['full_name']
    end

    def description
      @repo['description']
    end

    def url
      @repo['html_url']
    end

    def releases
      releases = []
      @releases.each do |r|
        if r['prerelease']
          releases << r if releases.empty?
        else
          releases << r
          break
        end
      end
      releases.map { |r| Release.new(r) }
    end
  end

  class Release
    def initialize(data)
      @data = data
    end

    def id
      @data['id']
    end

    def name
      @data['name']
    end

    def url
      @data['html_url']
    end

    def prerelease
      @data['prerelease']
    end

    def assets
      @data['assets']
    end

    def binaries
      assets.
        select { |d| d['name'] }.
        map { |d| Binary.new(d) }
    end
  end

  class Binary
    def initialize(data)
      @data = data
    end

    def name
      @data['name']
    end

    def url
      @data['browser_download_url']
    end

    def kind
      'Binary'
    end

    def ext 
      %w[.tar.gz .zip .rpm].find {|ext| @data['name'].end_with?(ext)} || ""
    end

    def type
      (base_name.downcase.include? "gpg") ? "gpg" : ext.split('.',2).last
    end

    def os
      case ext
      when ".rpm"
        base_name.rpartition(".").first.split(".").last
      when ""
        ""
      else
        base_name.split('.').last.split('-').first
      end
    end

    def arch
      case ext
      when ".rpm"
        base_name.split('.').last
      when ""
        ""
      else
        base_name.split('.').last.split('-').last
      end
    end

    def size
      @data['size']
    end

    private

    def base_name
      name.chomp('.tar.gz').chomp('.zip').chomp('.rpm')
    end
  end

  module Helper
    def format_bytes(bytes)
      '%.2f MiB' % (bytes.to_f / 1024 / 1024)
    end

    def dropdown(name, items, default, groups = {})
      additional = groups.map do |name, items|
        %(<li data-group="#{items.join(' ')}"><a href="#">#{name}</a></li>)
      end.join('')

      caption = %(<span class="caption">#{default}</span> <span class="caret"></span>)
      button = %(<button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">#{caption}</button>)
      header = %(<li><a href="#">all</a></li>#{additional}<li role="separator" class="divider"></li>)
      list = %(<ul class="dropdown-menu">#{header} #{items.map { |i| %(<li><a href="#">#{i}</a></li>) }.join('') }</ul>)

      %(<div class="btn-group #{name}">#{button} #{list}</div>)
    end
  end
end

include Downloads::Helper
