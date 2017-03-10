require "test_helper"
require "tus/storage/gridfs"
require "logger"
require "stringio"

describe Tus::Storage::Gridfs do
  before do
    @storage = gridfs
  end

  after do
    @storage.bucket.files_collection.find.delete_many
    @storage.bucket.chunks_collection.find.delete_many
  end

  def gridfs(**options)
    client = Mongo::Client.new("mongodb://127.0.0.1:27017/mydb", logger: Logger.new(nil))
    Tus::Storage::Gridfs.new(client: client, **options)
  end

  describe "#create_file" do
    it "creates an empty file" do
      @storage.create_file(uid = "foo", {"Foo" => "Bar"})
      assert_equal "", @storage.read_file("foo")
      assert_equal Hash["Foo" => "Bar"], @storage.read_info("foo")
    end
  end

  describe "file_exists?" do
    it "returns true if file exists" do
      @storage.create_file("foo")
      assert_equal true, @storage.file_exists?("foo")
    end

    it "returns false if file doesn't exist" do
      assert_equal false, @storage.file_exists?("unknown")
    end
  end

  describe "#read_file" do
    it "returns contents of the file" do
      @storage.create_file("foo")
      @storage.patch_file("foo", StringIO.new("content"))
      assert_equal "content", @storage.read_file("foo")
    end
  end

  describe "#patch_file" do
    it "appends to the content" do
      @storage.create_file("foo")
      @storage.patch_file("foo", StringIO.new("hello"))
      @storage.patch_file("foo", StringIO.new(" world"))
      assert_equal 3, @storage.bucket.chunks_collection.find.count
      assert_equal "hello world", @storage.read_file("foo")
    end

    it "sets :chunkSize from the input size" do
      @storage.create_file("foo")
      assert_equal nil, @storage.bucket.files_collection.find(filename: "foo").first[:chunkSize]
      @storage.patch_file("foo", StringIO.new("hello"))
      assert_equal 5, @storage.bucket.files_collection.find(filename: "foo").first[:chunkSize]
      assert_equal 1, @storage.bucket.chunks_collection.find.count
    end

    it "allow setting :chunkSize in initializer" do
      @storage = gridfs(chunk_size: 1)
      @storage.create_file("foo")
      assert_equal 1, @storage.bucket.files_collection.find(filename: "foo").first[:chunkSize]
      @storage.patch_file("foo", StringIO.new("hello"))
      assert_equal 1, @storage.bucket.files_collection.find(filename: "foo").first[:chunkSize]
      assert_equal 5, @storage.bucket.chunks_collection.find.count
    end

    it "updates :length and :uploadDate" do
      @storage.create_file("foo")
      original_info = @storage.bucket.files_collection.find(filename: "foo").first
      @storage.patch_file("foo", StringIO.new("hello"))
      new_info = @storage.bucket.files_collection.find(filename: "foo").first
      assert_equal 5, new_info[:length]
      assert_operator new_info[:uploadDate], :>, original_info[:uploadDate]
    end

    it "patch with Tus::Input input from file" do
      begin
        @storage.create_file("foo")

        tmpfile = Tempfile.new
        tmpfile.write("hello world")
        tmpfile.rewind

        input = Tus::Input.new(tmpfile)

        @storage.patch_file("foo", input)
        assert_equal 1, @storage.bucket.chunks_collection.find.count
        assert_equal "hello world", @storage.read_file("foo")
      ensure
        tmpfile.close!
      end
    end

    it "patch with Tus::Input from string" do
      @storage.create_file("foo")

      io = StringIO.new("hello world")

      input = Tus::Input.new(io)

      @storage.patch_file("foo", input)
      assert_equal 1, @storage.bucket.chunks_collection.find.count
      assert_equal "hello world", @storage.read_file("foo")
    end
  end

  describe "#get_file" do
    it "returns the response that responds to #each" do
      @storage = gridfs(chunk_size: 2)
      @storage.create_file("foo")
      @storage.patch_file("foo", StringIO.new("hello world"))
      response = @storage.get_file("foo")
      assert_equal ["he", "ll", "o ", "wo", "rl", "d"], response.each.map(&:dup)
      response.close
    end

    it "supports partial responses" do
      @storage = gridfs(chunk_size: 3)
      @storage.create_file("foo")
      @storage.patch_file("foo", StringIO.new("hello world"))

      response = @storage.get_file("foo", range: 0..11)
      assert_equal ["hel", "lo ", "wor", "ld"], response.each.map(&:dup)

      response = @storage.get_file("foo", range: 6..11)
      assert_equal ["wor", "ld"], response.each.map(&:dup)

      response = @storage.get_file("foo", range: 4..6)
      assert_equal ["o ", "w"], response.each.map(&:dup)
    end
  end

  describe "#delete_file" do
    it "deletes the file" do
      @storage.create_file("foo")
      @storage.delete_file("foo")
      assert_equal false, @storage.file_exists?("foo")
    end

    it "doesn't fail when file doesn't exist" do
      @storage.delete_file("foo")
    end
  end

  describe "#read_info" do
    it "reads info" do
      @storage.create_file("foo")
      assert_equal Hash.new, @storage.read_info("foo")

      @storage.create_file("bar", {"Foo" => "Bar"})
      assert_equal Hash["Foo" => "Bar"], @storage.read_info("bar")
    end
  end

  describe "#update_info" do
    it "replaces existing info" do
      @storage.create_file("foo", {"Foo" => "Foo"})
      @storage.update_info("foo", {"Bar" => "Bar"})
      assert_equal Hash["Bar" => "Bar"], @storage.read_info("foo")
    end
  end

  describe "#list_files" do
    it "returns list of uids" do
      @storage.create_file("foo")
      @storage.create_file("bar")
      assert_equal ["foo", "bar"], @storage.list_files
    end
  end
end
