# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "helper"
require "json"
require "uri"

describe Google::Cloud::Storage::File, :mock_storage do
  let(:bucket_gapi) { Google::Apis::StorageV1::Bucket.from_json random_bucket_hash("bucket").to_json }
  let(:bucket) { Google::Cloud::Storage::Bucket.from_gapi bucket_gapi, storage.service }

  let(:file_hash) { random_file_hash bucket.name, "file.ext" }
  let(:file_gapi) { Google::Apis::StorageV1::Object.from_json file_hash.to_json }
  let(:file) { Google::Cloud::Storage::File.from_gapi file_gapi, storage.service }

  let(:encryption_key) { "y\x03\"\x0E\xB6\xD3\x9B\x0E\xAB*\x19\xFAv\xDEY\xBEI\xF8ftA|[z\x1A\xFBE\xDE\x97&\xBC\xC7" }
  let(:encryption_key_sha256) { "5\x04_\xDF\x1D\x8A_d\xFEK\e6p[XZz\x13s]E\xF6\xBB\x10aQH\xF6o\x14f\xF9" }
  let(:key_headers) do {
      "x-goog-encryption-algorithm"  => "AES256",
      "x-goog-encryption-key"        => Base64.strict_encode64(encryption_key),
      "x-goog-encryption-key-sha256" => Base64.strict_encode64(encryption_key_sha256)
    }
  end
  let(:copy_key_headers) do {
      "x-goog-copy-source-encryption-algorithm"  => "AES256",
      "x-goog-copy-source-encryption-key"        => Base64.strict_encode64(encryption_key),
      "x-goog-copy-source-encryption-key-sha256" => Base64.strict_encode64(encryption_key_sha256),
      "x-goog-encryption-algorithm"  => "AES256",
      "x-goog-encryption-key"        => Base64.strict_encode64(encryption_key),
      "x-goog-encryption-key-sha256" => Base64.strict_encode64(encryption_key_sha256)
    }
  end
  let(:key_options) { { header: key_headers } }
  let(:copy_key_options) { { header: copy_key_headers } }

  let(:source_encryption_key) { "T\x80\xC2}\x91R\xD2\x05\fTo\xD4\xB3+\xAE\xBCbd\xD1\x81|\xCD\x06%\xC8|\xA2\x17\xF6\xB4^\xD0" }
  let(:source_encryption_key_sha256) { "\x03(M#\x1D(BF\x12$T\xD4\xDCP\xE6\x98\a\xEB'\x8A\xB9\x89\xEEM)\x94\xFD\xE3VR*\x86" }
  let(:source_key_headers) do {
      "x-goog-copy-source-encryption-algorithm"  => "AES256",
      "x-goog-copy-source-encryption-key"        => Base64.strict_encode64(source_encryption_key),
      "x-goog-copy-source-encryption-key-sha256" => Base64.strict_encode64(source_encryption_key_sha256)
    }
  end


  it "knows its attributes" do
    file.id.must_equal file_hash["id"]
    file.name.must_equal file_hash["name"]
    file.created_at.must_be_within_delta file_hash["timeCreated"].to_datetime
    file.api_url.must_equal file_hash["selfLink"]
    file.media_url.must_equal file_hash["mediaLink"]
    file.public_url.must_equal "https://storage.googleapis.com/#{file.bucket}/#{file.name}"
    file.public_url(protocol: :http).must_equal "http://storage.googleapis.com/#{file.bucket}/#{file.name}"
    file.url.must_equal file.public_url

    file.md5.must_equal file_hash["md5Hash"]
    file.crc32c.must_equal file_hash["crc32c"]
    file.etag.must_equal file_hash["etag"]

    file.cache_control.must_equal "public, max-age=3600"
    file.content_disposition.must_equal "attachment; filename=filename.ext"
    file.content_encoding.must_equal "gzip"
    file.content_language.must_equal "en"
    file.content_type.must_equal "text/plain"

    file.metadata.must_be_kind_of Hash
    file.metadata.size.must_equal 2
    file.metadata.frozen?.must_equal true
    file.metadata["player"].must_equal "Alice"
    file.metadata["score"].must_equal "101"
  end

  it "can delete itself" do
    mock = Minitest::Mock.new
    mock.expect :delete_object, nil, [bucket.name, file.name]

    file.service.mocked_service = mock

    file.delete

    mock.verify
  end

  it "can download itself to a file" do
    # Stub the md5 to match.
    def file.md5
      "1B2M2Y8AsgTpgAmY7PhCfg=="
    end

    Tempfile.open "google-cloud" do |tmpfile|
      # write to the file since the mocked call won't
      tmpfile.write "yay!"

      mock = Minitest::Mock.new
      mock.expect :get_object, tmpfile,
        [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: {}]

      bucket.service.mocked_service = mock

      downloaded = file.download tmpfile
      downloaded.must_be_kind_of File

      mock.verify
    end
  end

  it "can download itself to a file by path" do
    # Stub the md5 to match.
    def file.md5
      "1B2M2Y8AsgTpgAmY7PhCfg=="
    end

    Tempfile.open "google-cloud" do |tmpfile|
      # write to the file since the mocked call won't
      tmpfile.write "yay!"

      mock = Minitest::Mock.new
      mock.expect :get_object, tmpfile,
        [bucket.name, file.name, download_dest: tmpfile.path, generation: nil, options: {}]

      bucket.service.mocked_service = mock

      downloaded = file.download tmpfile.path
      downloaded.must_be_kind_of File

      mock.verify
    end
  end

  it "can download itself to an IO" do
    # Stub the md5 to match.
    def file.md5
      "X7A8HRvZUCT5gbq0KNDL8Q=="
    end

    mock = Minitest::Mock.new
    mock.expect :get_object, StringIO.new("yay!"),
      [bucket.name, file.name, Hash] # Can't match StringIO in mock...

    bucket.service.mocked_service = mock

    downloaded = file.download
    downloaded.must_be_kind_of StringIO

    mock.verify
  end

  it "can download itself by specifying an IO" do
    # Stub the md5 to match.
    def file.md5
      "X7A8HRvZUCT5gbq0KNDL8Q=="
    end

    mock = Minitest::Mock.new
    mock.expect :get_object, StringIO.new("yay!"),
      [bucket.name, file.name, Hash] # Can't match StringIO in mock...

    bucket.service.mocked_service = mock

    downloadio = StringIO.new
    downloaded = file.download downloadio
    downloaded.must_be_kind_of StringIO
    downloadio.must_equal downloadio # should be the same object

    mock.verify
  end

  it "can download itself with customer-supplied encryption key" do
    # Stub the md5 to match.
    def file.md5
      "1B2M2Y8AsgTpgAmY7PhCfg=="
    end

    Tempfile.open "google-cloud" do |tmpfile|
      # write to the file since the mocked call won't
      tmpfile.write "yay!"

      mock = Minitest::Mock.new
      mock.expect :get_object, nil, # using encryption keys seems to return nil
        [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: key_options]

      bucket.service.mocked_service = mock

      downloaded = file.download tmpfile, encryption_key: encryption_key
      downloaded.path.must_equal tmpfile.path

      mock.verify
    end
  end

  describe "verified downloads" do
    it "verifies m5d by default" do
      # Stub these values
      def file.md5; "md5="; end
      def file.crc32c; "crc32c="; end

      Tempfile.open "google-cloud" do |tmpfile|
        mock = Minitest::Mock.new
        mock.expect :get_object, tmpfile,
          [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: {}]

        bucket.service.mocked_service = mock

        mocked_md5 = Minitest::Mock.new
        mocked_md5.expect :md5_mock, file.md5
        stubbed_md5 = lambda { |_| mocked_md5.md5_mock }
        stubbed_crc32c = lambda { |_| fail "Should not be called!" }

        Google::Cloud::Storage::File::Verifier.stub :md5_for, stubbed_md5 do
          Google::Cloud::Storage::File::Verifier.stub :crc32c_for, stubbed_crc32c do
            file.download tmpfile
          end
        end
        mocked_md5.verify
        mock.verify
      end
    end

    it "verifies m5d when specified" do
      # Stub these values
      def file.md5; "md5="; end
      def file.crc32c; "crc32c="; end

      Tempfile.open "google-cloud" do |tmpfile|
        mock = Minitest::Mock.new
        mock.expect :get_object, tmpfile,
          [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: {}]

        bucket.service.mocked_service = mock

        mocked_md5 = Minitest::Mock.new
        mocked_md5.expect :md5_mock, file.md5
        stubbed_md5 = lambda { |_| mocked_md5.md5_mock }
        stubbed_crc32c = lambda { |_| fail "Should not be called!" }

        Google::Cloud::Storage::File::Verifier.stub :md5_for, stubbed_md5 do
          Google::Cloud::Storage::File::Verifier.stub :crc32c_for, stubbed_crc32c do
            file.download tmpfile, verify: :md5
          end
        end
        mocked_md5.verify
        mock.verify
      end
    end

    it "verifies crc32c when specified" do
      # Stub these values
      def file.md5; "md5="; end
      def file.crc32c; "crc32c="; end

      Tempfile.open "google-cloud" do |tmpfile|
        mock = Minitest::Mock.new
        mock.expect :get_object, tmpfile,
          [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: {}]

        bucket.service.mocked_service = mock

        stubbed_md5 = lambda { |_| fail "Should not be called!" }
        mocked_crc32c = Minitest::Mock.new
        mocked_crc32c.expect :crc32c_mock, file.crc32c
        stubbed_crc32c = lambda { |_| mocked_crc32c.crc32c_mock }

        Google::Cloud::Storage::File::Verifier.stub :md5_for, stubbed_md5 do
          Google::Cloud::Storage::File::Verifier.stub :crc32c_for, stubbed_crc32c do
            file.download tmpfile, verify: :crc32c
          end
        end
        mocked_crc32c.verify
        mock.verify
      end
    end

    it "verifies m5d and crc32c when specified" do
      # Stub these values
      def file.md5; "md5="; end
      def file.crc32c; "crc32c="; end

      Tempfile.open "google-cloud" do |tmpfile|
        mock = Minitest::Mock.new
        mock.expect :get_object, tmpfile,
          [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: {}]

        bucket.service.mocked_service = mock

        mocked_md5 = Minitest::Mock.new
        mocked_md5.expect :md5_mock, file.md5
        stubbed_md5 = lambda { |_| mocked_md5.md5_mock }

        mocked_crc32c = Minitest::Mock.new
        mocked_crc32c.expect :crc32c_mock, file.crc32c
        stubbed_crc32c = lambda { |_| mocked_crc32c.crc32c_mock }

        Google::Cloud::Storage::File::Verifier.stub :md5_for, stubbed_md5 do
          Google::Cloud::Storage::File::Verifier.stub :crc32c_for, stubbed_crc32c do
            file.download tmpfile, verify: :all
          end
        end
        mocked_md5.verify
        mocked_crc32c.verify
        mock.verify
      end
    end

    it "doesn't verify at all when specified" do
      # Stub these values
      def file.md5; "md5="; end
      def file.crc32c; "crc32c="; end

      Tempfile.open "google-cloud" do |tmpfile|
        mock = Minitest::Mock.new
        mock.expect :get_object, tmpfile,
          [bucket.name, file.name, download_dest: tmpfile, generation: nil, options: {}]

        bucket.service.mocked_service = mock

        stubbed_md5 = lambda { |_| fail "Should not be called!" }
        stubbed_crc32c = lambda { |_| fail "Should not be called!" }

        Google::Cloud::Storage::File::Verifier.stub :md5_for, stubbed_md5 do
          Google::Cloud::Storage::File::Verifier.stub :crc32c_for, stubbed_crc32c do
            file.download tmpfile, verify: :none
          end
        end

        mock.verify
      end
    end

    it "raises when verification fails" do
      # Stub these values
      def file.md5; "md5="; end
      def file.crc32c; "crc32c="; end

      Tempfile.open "google-cloud" do |tmpfile|
        mock = Minitest::Mock.new
        mock.expect :get_object, tmpfile,
          [bucket.name, file.name, download_dest: tmpfile.path, generation: nil, options: {}]

        bucket.service.mocked_service = mock

        mocked_md5 = Minitest::Mock.new
        mocked_md5.expect :md5_mock, "NOPE="
        stubbed_md5 = lambda { |_| mocked_md5.md5_mock }
        stubbed_crc32c = lambda { |_| fail "Should not be called!" }

        Google::Cloud::Storage::File::Verifier.stub :md5_for, stubbed_md5 do
          Google::Cloud::Storage::File::Verifier.stub :crc32c_for, stubbed_crc32c do
            assert_raises Google::Cloud::Storage::FileVerificationError do
              file.download tmpfile.path
            end
          end
        end
        mocked_md5.verify
        mock.verify
      end
    end
  end

  it "can copy itself in the same bucket" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-file.ext"

    mock.verify
  end

  it "can copy itself in the same bucket with generation" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: 123, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-file.ext", generation: 123

    mock.verify
  end

  it "can copy itself in the same bucket with predefined ACL" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: "private", source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-file.ext", acl: "private"

    mock.verify
  end

  it "can copy itself in the same bucket with ACL alias" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: "publicRead", source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-file.ext", acl: :public

    mock.verify
  end

  it "can copy itself with customer-supplied encryption key" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: nil, options: copy_key_options]

    file.service.mocked_service = mock

    file.copy "new-file.ext", encryption_key: encryption_key

    mock.verify
  end

  it "can copy itself to a different bucket" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, "new-bucket", "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-bucket", "new-file.ext"

    mock.verify
  end

  it "can copy itself to a different bucket with generation" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, "new-bucket", "new-file.ext", nil, destination_predefined_acl: nil, source_generation: 123, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-bucket", "new-file.ext", generation: 123

    mock.verify
  end

  it "can copy itself to a different bucket with predefined ACL" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, "new-bucket", "new-file.ext", nil, destination_predefined_acl: "private", source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-bucket", "new-file.ext", acl: "private"

    mock.verify
  end

  it "can copy itself to a different bucket with ACL alias" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, "new-bucket", "new-file.ext", nil, destination_predefined_acl: "publicRead", source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-bucket", "new-file.ext", acl: :public

    mock.verify
  end

  it "can copy itself to a different bucket with customer-supplied encryption key" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, "new-bucket", "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: nil, options: copy_key_options]

    file.service.mocked_service = mock

    file.copy "new-bucket", "new-file.ext", encryption_key: encryption_key

    mock.verify
  end

  it "can copy itself calling rewrite multiple times" do
    mock = Minitest::Mock.new
    mock.expect :rewrite_object, undone_rewrite("notyetcomplete"),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: nil, options: {}]
    mock.expect :rewrite_object, undone_rewrite("keeptrying"),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: "notyetcomplete", options: {}]
    mock.expect :rewrite_object, undone_rewrite("almostthere"),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: "keeptrying", options: {}]
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", nil, destination_predefined_acl: nil, source_generation: nil, rewrite_token: "almostthere", options: {}]

    file.service.mocked_service = mock

    # mock out sleep to make the test run faster
    def file.sleep *args
    end

    file.copy "new-file.ext"

    mock.verify
  end

  it "can copy itself while updating its attributes" do
    mock = Minitest::Mock.new
    update_file_gapi = Google::Apis::StorageV1::Object.new(
      cache_control: "private, max-age=0, no-cache",
      content_disposition: "inline; filename=filename.ext",
      content_encoding: "deflate",
      content_language: "de",
      content_type: "application/json",
      metadata: { "player" => "Bob", "score" => "10" },
      storage_class: "NEARLINE"
    )
    mock.expect :rewrite_object, done_rewrite(file_gapi),
      [bucket.name, file.name, bucket.name, "new-file.ext", update_file_gapi, destination_predefined_acl: nil, source_generation: nil, rewrite_token: nil, options: {}]

    file.service.mocked_service = mock

    file.copy "new-file.ext" do |f|
      f.cache_control = "private, max-age=0, no-cache"
      f.content_disposition = "inline; filename=filename.ext"
      f.content_encoding = "deflate"
      f.content_language = "de"
      f.content_type = "application/json"
      f.metadata["player"] = "Bob"
      f.metadata["score"] = "10"
      f.storage_class = :nearline
    end

    mock.verify
  end

  it "can rotate its customer-supplied encryption keys" do
    mock = Minitest::Mock.new
    options = { header: source_key_headers.merge(key_headers) }
    mock.expect :rewrite_object, done_rewrite(file_gapi),
                [bucket.name, file.name, bucket.name, file.name, nil,
                 destination_predefined_acl: nil, source_generation: nil,
                 rewrite_token: nil, options: options ]

    file.service.mocked_service = mock

    updated = file.rotate encryption_key: source_encryption_key, new_encryption_key: encryption_key
    updated.name.must_equal file.name

    mock.verify
  end

  it "can rotate to a customer-supplied encryption key if previously unencrypted with customer key" do
    mock = Minitest::Mock.new
    options = { header: key_headers }
    mock.expect :rewrite_object, done_rewrite(file_gapi),
                [bucket.name, file.name, bucket.name, file.name, nil,
                 destination_predefined_acl: nil, source_generation: nil,
                 rewrite_token: nil, options: options ]

    file.service.mocked_service = mock

    updated = file.rotate new_encryption_key: encryption_key
    updated.name.must_equal file.name

    mock.verify
  end

  it "can rotate from a customer-supplied encryption key to default service encryption" do
    mock = Minitest::Mock.new
    options = { header: source_key_headers }
    mock.expect :rewrite_object, done_rewrite(file_gapi),
                [bucket.name, file.name, bucket.name, file.name, nil,
                 destination_predefined_acl: nil, source_generation: nil,
                 rewrite_token: nil, options: options ]

    file.service.mocked_service = mock

    updated = file.rotate encryption_key: source_encryption_key
    updated.name.must_equal file.name

    mock.verify
  end

  it "can rotate its customer-supplied encryption keys with multiple requests for large objects" do
    mock = Minitest::Mock.new
    options = { header: source_key_headers.merge(key_headers) }
    mock.expect :rewrite_object, undone_rewrite("notyetcomplete"),
                [bucket.name, file.name, bucket.name, file.name, nil,
                 destination_predefined_acl: nil, source_generation: nil,
                 rewrite_token: nil, options: options ]
    mock.expect :rewrite_object, done_rewrite(file_gapi),
                [bucket.name, file.name, bucket.name, file.name, nil,
                 destination_predefined_acl: nil, source_generation: nil,
                 rewrite_token: "notyetcomplete", options: options ]

    file.service.mocked_service = mock

    # mock out sleep to make the test run faster
    def file.sleep *args
    end

    updated = file.rotate encryption_key: source_encryption_key, new_encryption_key: encryption_key
    updated.name.must_equal file.name

    mock.verify
  end

  it "can reload itself" do
    file_name = "file.ext"

    mock = Minitest::Mock.new
    mock.expect :get_object, Google::Apis::StorageV1::Object.from_json(random_file_hash(bucket.name, file_name, 1234567891).to_json),
      [bucket.name, file_name, generation: nil, options: {}]
    mock.expect :get_object, Google::Apis::StorageV1::Object.from_json(random_file_hash(bucket.name, file_name, 1234567892).to_json),
      [bucket.name, file_name, generation: nil, options: {}]

    bucket.service.mocked_service = mock
    file.service.mocked_service = mock

    file = bucket.file file_name
    file.generation.must_equal 1234567891
    file.reload!
    file.generation.must_equal 1234567892

    mock.verify
  end
end
