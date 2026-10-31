# frozen_string_literal: true

# Redmine plugin for Document Management System "Features"
#
# Karel Pičman <karel.picman@kontron.com>
#
# This file is part of Redmine DMSF plugin.
#
# Redmine DMSF plugin is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# Redmine DMSF plugin is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
# the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with Redmine DMSF plugin. If not, see
# <https://www.gnu.org/licenses/>.

module RedmineDmsf
  module Hooks
    module Views
      # Issue view hooks
      class IssueViewHooks < Redmine::Hook::ViewListener
        include DmsfQueriesHelper
        include DmsfFilesHelper

        def view_issues_form_details_bottom(context = {})
          context[:container] = context[:issue]
          attach_documents_form(context)
        end

        def view_issues_show_description_bottom(context = {})
          show_attached_documents context[:issue], context[:controller]
        end

        private

        def allowed_to_attach_documents?(container)
          return false unless container.respond_to?(:project) && container.respond_to?(:saved_dmsf_attachments) &&
                              RedmineDmsf.dmsf_act_as_attachable?

          return false if container.project && (!User.current.allowed_to?(:file_manipulation, container.project) ||
            (container.project&.dmsf_act_as_attachable != Project::ATTACHABLE_DMS_AND_ATTACHMENTS))

          true
        end

        def get_links(container)
          links = []
          if defined?(container.dmsf_files) &&
             User.current.allowed_to?(:view_dmsf_files, container.project) &&
             RedmineDmsf.dmsf_act_as_attachable? &&
             container.project.dmsf_act_as_attachable == Project::ATTACHABLE_DMS_AND_ATTACHMENTS
            container.dmsf_files.each do |dmsf_file|
              links << [dmsf_file, nil, dmsf_file.created_at] if dmsf_file.last_revision
            end
            container.dmsf_links.each do |dmsf_link|
              dmsf_file = dmsf_link.target_file
              links << [dmsf_file, dmsf_link, dmsf_link.created_at] if dmsf_file&.last_revision && !dmsf_file.deleted?
            end
            # Sort by 'create_at'
            links.sort_by! { |a| a[2] }
          end
          links
        end

        def attach_documents_form(context, label: true)
          return unless context.is_a?(Hash) && context[:container]

          # Add Dmsf upload form
          container = context[:container]
          return unless allowed_to_attach_documents?(container)

          html = +'<p'
          html << ' style="display: none;"' if User.current.pref.dmsf_attachments_upload_choice == 'Attachments'
          html << '>'
          if label
            html << "<label>#{l(:label_dmsf_upload_to_dms)}</label>"
            html << '<span class="attachments-container dmsf-uploader">'
          else
            html << %(<span class="attachments-container dmsf-uploader"
              style="border: 2px dashed #dfccaf; background: none;">)
          end
          html << context[:controller].send(:render_to_string, { partial: 'dmsf_upload/form',
                                                                 locals: { container: container,
                                                                           multiple: true,
                                                                           awf: true } })
          html << '</span>'
          html << '</p>'
          html
        end

        def show_attached_documents(container, controller, _attachments = nil)
          # Add list of attached documents
          links = get_links(container)
          return if links.blank?

          controller.send :render_to_string,
                          { partial: 'dmsf_files/links',
                            locals: { links: links, thumbnails: Setting.thumbnails_enabled? } }
        end
      end
    end
  end
end
