# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++
require "spec_helper"

RSpec.describe OpenIDConnect::JwtParser do
  subject(:parse) { described_class.new.parse(token) }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:payload) { { "sub" => "M. Curie", "iss" => "International Space Station", "aud" => our_client_id } }
  let(:token) { JWT.encode(payload, private_key, "RS256", { kid: "key-identifier" }) }

  let!(:provider) { create(:oidc_provider) }
  let(:known_issuer) { "International Space Station" }
  let(:our_client_id) { "openproject.org" }

  before do
    allow(JSON::JWK::Set::Fetcher).to receive(:fetch).and_return(
      instance_double(JSON::JWK, to_key: private_key.public_key)
    )

    provider.options["issuer"] = known_issuer
    provider.options["client_id"] = our_client_id
    provider.options["jwks_uri"] = "https://example.com/certs"
    provider.save!
  end

  it "parses the token" do
    parsed, = parse
    expect(parsed).to eq payload
  end

  it "returns the provider configuration for the associated provider" do
    _, p = parse
    expect(p).to eq provider
  end

  it "correctly queries for the token's public key" do
    parse

    expect(JSON::JWK::Set::Fetcher).to have_received(:fetch).with("https://example.com/certs", kid: "key-identifier")
  end

  context "when the provider signing the token is not known" do
    let(:known_issuer) { "Lunar Gateway" }

    it "raises an error" do
      expect { parse }.to raise_error(OpenIDConnect::JwtParser::Error, /issuer is unknown/)
    end
  end

  context "when the provider signing the token is not available" do
    before do
      provider.update!(available: false)
    end

    it "raises an error" do
      expect { parse }.to raise_error(OpenIDConnect::JwtParser::Error, /issuer is unknown/)
    end
  end

  context "when the token is not a valid JWT" do
    let(:token) { Base64.encode64("banana").strip }

    it "raises an error" do
      expect { parse }.to raise_error(JWT::DecodeError)
    end
  end

  context "when the token is signed using an unsupported signature" do
    let(:token) { JWT.encode(payload, "secret", "HS256", { kid: "key-identifier" }) }

    it "raises an error" do
      expect { parse }.to raise_error(OpenIDConnect::JwtParser::Error, /HS256 is not supported/)
    end
  end

  context "when we are not the token's audience" do
    before do
      payload["aud"] = "Alice"
    end

    it "raises an error" do
      expect { parse }.to raise_error(JWT::InvalidAudError)
    end

    context "and the audience shall not be verified" do
      subject(:parse) { described_class.new(verify_audience: false).parse(token) }

      it "parses the token" do
        parsed, = parse
        expect(parsed).to eq payload
      end
    end
  end

  context "when the token does not indicate a Key Identifier" do
    let(:token) { JWT.encode(payload, private_key, "RS256") }

    it "raises an error" do
      expect { parse }.to raise_error(OpenIDConnect::JwtParser::Error, /Key Identifier .+ is missing/)
    end
  end

  context "when requiring a specific claim" do
    subject(:parse) { described_class.new(required_claims: ["sub"]).parse(token) }

    it "parses the token" do
      parsed, = parse
      expect(parsed).to eq payload
    end

    context "and when the required claim is missing" do
      before do
        payload.delete("sub")
      end

      it "raises an error" do
        expect { parse }.to raise_error(JWT::MissingRequiredClaim)
      end
    end
  end
end
