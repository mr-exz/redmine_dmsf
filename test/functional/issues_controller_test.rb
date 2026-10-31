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

require File.expand_path('../../test_helper', __FILE__)

# Issues controller
class IssuesControllerTest < RedmineDmsf::Test::TestCase
  def setup
    super
    @issue1 = Issue.find 1
    post '/login', params: { username: 'jsmith', password: 'jsmith' }
  end

  def test_put_update_with_project_change
    # If we move an issue to a different project, attached documents and their system folders must be moved too
    assert_equal @issue1.project, @project1
    system_folder = @issue1.system_folder
    assert system_folder
    assert_equal @project1.id, system_folder.project_id
    main_system_folder = @issue1.main_system_folder
    assert main_system_folder
    assert_equal @project1.id, main_system_folder.project_id
    patch "/issues/#{@issue1.id}",
          params: { issue: { project_id: @project2.id, tracker_id: '1', priority_id: '6', category_id: '3' } }
    assert_redirected_to action: 'show', id: @issue1.id
    @issue1.reload
    assert_equal @project2.id, @issue1.project.id
    system_folder = @issue1.system_folder
    assert system_folder
    assert_equal @project2.id, system_folder.project_id
    main_system_folder = @issue1.main_system_folder
    assert main_system_folder
    assert_equal @project2.id, main_system_folder.project_id
  end

  def upload_to_issue(target, filename: 'picked.txt')
    attachment = Attachment.create!(file: StringIO.new('content'), filename: filename, content_type: 'text/plain',
                                    author: @jsmith)
    with_settings plugin_redmine_dmsf: Setting.plugin_redmine_dmsf.merge('dmsf_act_as_attachable' => '1') do
      patch "/issues/#{@issue1.id}",
            params: { issue: { notes: 'upload' }, dmsf_target_folder_id: target,
                      dmsf_attachments: { '1' => { filename: filename, token: attachment.token } } }
    end
    assert_redirected_to action: 'show', id: @issue1.id
  end

  def test_upload_without_a_folder_is_not_stored
    assert_no_difference 'DmsfFile.count' do
      upload_to_issue ''
    end
    assert_equal I18n.t(:warning_dmsf_target_folder_invalid), flash[:warning]
  end

  def test_upload_to_a_chosen_folder_is_linked_to_the_issue
    folder = DmsfFolder.find 1
    upload_to_issue folder.id.to_s
    file = DmsfFile.visible.find_file_by_name(@project1, folder, 'picked.txt')
    assert file
    assert_includes @issue1.dmsf_links.map(&:target_id), file.id
  end

  def test_upload_to_the_dms_root
    upload_to_issue DmsfFolder::UPLOAD_TARGET_ROOT
    assert DmsfFile.visible.find_file_by_name(@project1, nil, 'picked.txt')
  end

  def test_upload_of_an_existing_name_adds_a_revision_and_one_link
    folder = DmsfFolder.find 1
    2.times { upload_to_issue folder.id.to_s }
    file = DmsfFile.visible.find_file_by_name(@project1, folder, 'picked.txt')
    assert_equal 2, file.dmsf_file_revisions.visible.count
    newest, oldest = file.dmsf_file_revisions.to_a
    assert_operator newest.minor_version.to_i, :>, oldest.minor_version.to_i
    assert_equal(1, @issue1.dmsf_links.count { |l| l.target_id == file.id })
  end

  def test_upload_to_a_folder_of_another_project_is_not_stored
    assert_no_difference 'DmsfFile.count' do
      upload_to_issue DmsfFolder.find(3).id.to_s
    end
    assert_equal I18n.t(:warning_dmsf_target_folder_invalid), flash[:warning]
  end

  def test_system_folders_are_not_offered_as_targets
    assert @issue1.system_folder
    values = DmsfFolder.upload_targets(@project1)
    assert_not_includes values, @issue1.system_folder.id.to_s
    assert_not_includes values, @issue1.main_system_folder.id.to_s
  end

  def issue_page
    with_settings plugin_redmine_dmsf: Setting.plugin_redmine_dmsf.merge('dmsf_act_as_attachable' => '1') do
      get "/issues/#{@issue1.id}"
    end
    assert_response :success
  end

  def test_both_buttons_on_a_linked_file
    folder = DmsfFolder.find 1
    upload_to_issue folder.id.to_s
    issue_page
    file = DmsfFile.visible.find_file_by_name(@project1, folder, 'picked.txt')
    link = @issue1.dmsf_links.detect { |l| l.target_id == file.id }
    assert_select "a[title='Unlink'][href^='#{dmsf_link_path(link)}']"
    assert_select "a[title='#{I18n.t(:button_delete)}'][href^='#{dmsf_file_path(file)}']"
  end

  def test_file_chooser_is_disabled_until_a_folder_is_chosen
    with_settings plugin_redmine_dmsf: Setting.plugin_redmine_dmsf.merge('dmsf_act_as_attachable' => '1') do
      get "/issues/#{@issue1.id}/edit"
    end
    assert_select '.dmsf-uploader input.file_selector[disabled]'
    assert_select '.dmsf-folder-required'
  end

  def test_delete_sends_a_linked_file_to_the_trash_and_off_the_issue
    folder = DmsfFolder.find 1
    upload_to_issue folder.id.to_s
    file = DmsfFile.visible.find_file_by_name(@project1, folder, 'picked.txt')
    delete dmsf_file_path(file)
    assert file.reload.deleted?
    issue_page
    assert_not_includes response.body, 'picked.txt'
  end
end
