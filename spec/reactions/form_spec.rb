# frozen_string_literal: true

describe Reactions::Form do
	before do
		stub_const('YEAR_RANGE', 0..Time.now.year)

		stub_const(
			'Model', Class.new(Struct) do
				def self.all
					@all ||= []
				end

				def self.create(params)
					new(params).save
				end

				def self.find(params)
					all.find do |record|
						params.all? { |key, value| record.public_send(key) == value }
					end
				end

				def self.find_or_create(params)
					find(params) || new(params).save
				end

				def initialize(**columns)
					columns.each do |column, value|
						public_send "#{column}=", value
					end
				end

				def save
					all = self.class.all
					self.id ||= all.last&.id.to_i + 1
					all.delete_if { |record| record.id == id }
					all.push self
					self
				end
			end
		)

		stub_const(
			'Album', Model.new(:id, :title, :year, :artist)
		)

		## https://github.com/bbatsov/rubocop/issues/5830
		# rubocop:disable Lint/AccessModifierIndentation
		stub_const(
			'AlbumForm', Class.new(described_class) do
				field :title
				field :year, Integer

				def initialize(params)
					super
					@album = Album.new(fields)
				end

				private

				def validate
					errors.add('Album title is not present') if title.to_s.empty?

					return if YEAR_RANGE.include? year
					errors.add("Album year is not in #{YEAR_RANGE}")
				end

				def execute
					@album.save
				end
			end
		)
		# rubocop:enable Lint/AccessModifierIndentation
	end

	describe '.field' do
		it 'filters input params for #fields' do
			form_class = Class.new(described_class) do
				field :foo
				field :bar
			end

			form = form_class.new(foo: 1, bar: 2, baz: 3)

			expect(form.fields).to eq(foo: 1, bar: 2)
		end

		it 'make coercion to type as second parameter' do
			form_class = Class.new(described_class) do
				field :foo
				field :bar, Integer
				field :baz, String
			end

			form = form_class.new(foo: '1', bar: '2', baz: 3, qux: 4)

			expect(form.fields).to eq(foo: '1', bar: 2, baz: '3')
		end

		it 'raises error if there is no defined coercion to received type' do
			block = lambda do
				Class.new(described_class) do
					field :foo
					field :bar, Class
				end
			end

			expect(&block).to raise_error(
				Reactions::NoCoercionError, 'Reactions has no coercion to Class'
			)
		end
	end

	subject(:album_form) { AlbumForm.new(params) }

	let(:correct_album_params) { { title: 'Foo', year: 2018 } }

	describe '#fields' do
		subject { album_form.fields }

		context 'not enough params' do
			let(:params) { { title: 'Foo' } }

			it { is_expected.to eq(title: 'Foo') }
		end

		context 'enough params' do
			let(:params) { correct_album_params }

			it { is_expected.to eq(correct_album_params) }
		end

		context 'more than enough params' do
			let(:params) { correct_album_params.merge(artist: 'Bar') }

			it { is_expected.to eq(correct_album_params) }
		end
	end

	describe '#valid?' do
		subject { album_form.valid? }

		context 'correct params' do
			let(:params) { correct_album_params }

			it { is_expected.to be true }
		end

		context 'incorrect params' do
			let(:params) { { year: 3018 } }

			it { is_expected.to be false }
		end
	end

	describe '#errors' do
		before { album_form.valid? }
		subject { album_form.errors }

		context 'correct params' do
			let(:params) { correct_album_params }

			it { is_expected.to be_empty }
		end

		context 'incorrect params' do
			let(:params) { { year: 3018 } }

			it do
				is_expected.to eq(
					[
						'Album title is not present',
						"Album year is not in #{YEAR_RANGE}"
					].to_set
				)
			end
		end
	end

	describe '#run' do
		subject { album_form.run }

		context 'correct params' do
			let(:params) { correct_album_params }

			it 'runs execute and returns true' do
				is_expected.to be true
				expect(Album.all).to eq([Album.new(params.merge(id: 1))])
			end
		end

		context 'incorrect params' do
			let(:params) { { year: 3018 } }

			it 'does not run execute and returns false' do
				is_expected.to be false
				expect(Album.all).to be_empty
			end
		end
	end

	describe '.nested' do
		before do
			stub_const(
				'Artist', Model.new(:id, :name)
			)

			## https://github.com/bbatsov/rubocop/issues/5830
			# rubocop:disable Lint/AccessModifierIndentation
			stub_const(
				'ArtistForm', Class.new(described_class) do
					attr_reader :artist

					field :name

					private

					def validate
						return unless name.to_s.empty?
						errors.add('Artist name is not present')
					end

					def execute
						@artist = Artist.find_or_create(fields)
					end
				end
			)

			stub_const(
				'AlbumWithNestedForm', Class.new(AlbumForm) do
					nested :artist, ArtistForm

					private

					def execute
						@album.artist = artist
						super
					end
				end
			)
			# rubocop:enable Lint/AccessModifierIndentation
		end

		let(:album_with_nested_form) { AlbumWithNestedForm.new(params) }

		describe '#valid?' do
			subject { album_with_nested_form.valid? }

			context 'correct params' do
				let(:params) { correct_album_params.merge(artist: { name: 'Bar' }) }

				it { is_expected.to be true }
			end

			context 'incorrect params' do
				let(:params) { correct_album_params.merge(artist: { name: '' }) }

				it { is_expected.to be false }
			end
		end

		describe '#errors' do
			before { album_with_nested_form.valid? }
			subject { album_with_nested_form.errors }

			context 'correct params' do
				let(:params) { correct_album_params.merge(artist: { name: 'Bar' }) }

				it { is_expected.to be_empty }
			end

			context 'incorrect params' do
				let(:params) { { title: '', year: 2018, artist: { name: '' } } }

				it do
					is_expected.to eq(
						['Album title is not present', 'Artist name is not present'].to_set
					)
				end
			end
		end

		describe '#run' do
			subject { album_with_nested_form.run }

			context 'correct params' do
				let(:params) { correct_album_params.merge(artist: { name: 'Bar' }) }

				it 'runs execute of self and nested forms and returns true' do
					is_expected.to be true
					artist = Artist.new(id: 1, name: 'Bar')
					expect(Album.all).to eq([
						Album.new(correct_album_params.merge(id: 1, artist: artist))
					])
					expect(Artist.all).to eq([artist])
				end
			end

			context 'incorrect params' do
				let(:params) { { title: '', year: 2018, artist: { name: '' } } }

				it 'does not run execute of self and nested forms and returns false' do
					is_expected.to be false
					expect(Album.all).to be_empty
					expect(Artist.all).to be_empty
				end
			end
		end
	end
end