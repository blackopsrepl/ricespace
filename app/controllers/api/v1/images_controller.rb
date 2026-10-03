# frozen_string_literal: true

module Api
  module V1
    # The pictures on a page, over the API.
    #
    # The showcase endpoint sets the rice's facts; this one handles what those facts are
    # about — the screenshots themselves, and the account's profile picture. A folder on
    # somebody's computer has `assets/`, and a folder with pictures in it that cannot be
    # pushed is not a folder that holds the page.
    #
    # Two shapes here are shaped by the folder rather than by REST convention:
    #
    # * `record` names a build by its **title**, because a folder's `builds.json` holds
    #   titles and not ids — an id is the site's business, a title is the author's.
    # * order is set **whole**, in one request, because a folder has one order and the
    #   alternative is a `move` per picture, which is N requests to say one thing.
    #
    # Uploads are bounded in two places, and each bounds a different thing: the model bounds
    # one file (`ProfilePicture::MAX_BYTES` and friends), and the account bounds everything it
    # keeps (`User::STORAGE_LIMIT`, enforced by `CountedTowardStorage` on the models). This
    # controller checks the file's own ceiling before reading anything into a blob, because
    # refusing a 40 MB upload after storing it is not a limit — and lets the account ceiling
    # be applied by the records themselves, so the studio's forms and this endpoint cannot
    # disagree about it.
    class ImagesController < BaseController
      # POST /api/v1/images
      #
      # `kind` says what the picture is of: `shot` (a rice screenshot), `build`
      # (a hardware photo), or `picture` (the account's profile picture). `record` names
      # the build it belongs to — by title — and `caption` is the line shown under it.
      def create
        kind = params.require(:kind).to_s
        file = uploaded_file

        return fail_with(:bad_request, "missing_file", "no file was sent") if file.nil?

        case kind
        when "picture" then attach_profile_picture(file)
        when "shot" then attach_shot(file)
        when "build" then attach_build_photo(file)
        else fail_with(:unprocessable_content, "unknown_kind", "kind must be picture, shot or build")
        end
      end

      # DELETE /api/v1/images/:id?kind=shot
      #
      # `kind` says which table the id names, because the ids come from three different
      # tables and a bare number is ambiguous.
      def destroy
        kind = params.require(:kind).to_s

        case kind
        when "shot" then remove_shot
        when "build" then remove_build_photo
        else fail_with(:unprocessable_content, "unknown_kind", "kind must be shot or build")
        end
      end

      # PATCH /api/v1/images/order — the whole order at once.
      #
      # `{ kind: "shot", ids: [3, 1, 2] }` puts shot 3 first, then 1, then 2. Ids that do
      # not belong to the account are ignored rather than reported: a folder that has drifted
      # should converge, not fail, and the response says what the order actually became.
      def order
        kind = params.require(:kind).to_s
        ids = Array(params[:ids]).map(&:to_i)

        return fail_with(:unprocessable_content, "unknown_kind", "kind must be shot") unless kind == "shot"

        owned = current_user.showcase&.shots&.to_a || []
        by_id = owned.index_by(&:id)
        ordered = ids.filter_map { |id| by_id[id] }
        # Anything the folder did not name keeps its place, after the ones it did.
        ordered += owned.reject { |shot| ids.include?(shot.id) }

        ordered.each_with_index { |shot, position| shot.update_column(:position, position) }

        render json: { shots: ordered.map { |shot| shot_json(shot)[:shot] } }
      end

      private
        def uploaded_file
          upload = params[:file]
          return nil unless upload.respond_to?(:tempfile)

          upload
        end

        def bytes_of(upload)
          upload.respond_to?(:size) ? upload.size.to_i : 0
        end

        def too_big?(upload, limit)
          bytes_of(upload) > limit
        end

        def failure_for_uploads(record)
          fail_with(:unprocessable_content, "invalid_image", "the picture was not accepted",
            details: record.errors.full_messages)
        end

        def attach_profile_picture(file)
          return fail_with(:unprocessable_content, "file_too_large", "a profile picture must be smaller than #{ProfilePicture::MAX_BYTES / 1.megabyte} MB") if too_big?(file, ProfilePicture::MAX_BYTES)

          picture = current_user.profile_picture || current_user.build_profile_picture
          picture.image.attach(io: file.tempfile, filename: filename_of(file), content_type: content_type_of(file))
          return failure_for_uploads(picture) unless picture.save

          render json: { picture: { url: rails_blob_url(picture.image.blob), bytes: picture.image.blob.byte_size } }, status: :created
        end

        def attach_shot(file)
          return fail_with(:unprocessable_content, "file_too_large", "a shot must be smaller than #{ShowcaseShot::MAX_BYTES / 1.megabyte} MB") if too_big?(file, ShowcaseShot::MAX_BYTES)

          showcase = current_user.showcase || current_user.build_showcase
          shot = showcase.shots.build(caption: params[:caption])
          shot.image.attach(io: file.tempfile, filename: filename_of(file), content_type: content_type_of(file))
          return failure_for_uploads(shot) unless shot.save

          render json: shot_json(shot), status: :created
        end

        def attach_build_photo(file)
          build = find_build(params[:record])
          return fail_with(:not_found, "unknown_record", "no build with that title or id") if build.nil?

          photo = build.photos.build(caption: params[:caption])
          photo.image.attach(io: file.tempfile, filename: filename_of(file), content_type: content_type_of(file))
          return failure_for_uploads(photo) unless photo.save

          render json: { photo: { id: photo.id, caption: photo.caption, position: photo.position, bytes: photo.image.blob.byte_size } }, status: :created
        end

        # A folder names a build the way its author does — by title. An id is accepted too,
        # so a script that has one is not forced to look up the title first.
        def find_build(reference)
          value = reference.to_s
          return nil if value.blank?

          current_user.builds.find_by(title: value) || current_user.builds.find_by(id: value.to_i)
        end

        def remove_shot
          shot = current_user.showcase&.shots&.find_by(id: params[:id])
          return fail_with(:not_found, "unknown_shot", "no shot with that id") if shot.nil?

          shot.destroy!
          head :no_content
        end

        def remove_build_photo
          photo = current_user.builds.includes(:photos).flat_map(&:photos).find { |candidate| candidate.id == params[:id].to_i }
          return fail_with(:not_found, "unknown_photo", "no photo with that id") if photo.nil?

          photo.destroy!
          head :no_content
        end

        def shot_json(shot)
          { shot: {
              id: shot.id, caption: shot.caption, position: shot.position,
              bytes: shot.image.attached? ? shot.image.blob.byte_size : nil,
              url: shot.image.attached? ? rails_blob_url(shot.image.blob) : nil
            } }
        end

        def filename_of(upload)
          upload.respond_to?(:original_filename) ? upload.original_filename : "upload"
        end

        def content_type_of(upload)
          upload.respond_to?(:content_type) ? upload.content_type : "application/octet-stream"
        end
    end
  end
end
