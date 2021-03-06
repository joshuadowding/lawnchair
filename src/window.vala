/*
 * Copyright 2018 Abiola Ibrahim
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

[GtkTemplate (ui = "/com/github/joshuadowding/lawnchair/window.glade")]
public class LawnchairWindow: Gtk.ApplicationWindow {

    [GtkChild]
    Gtk.Grid application_grid;

    [GtkChild]
    Gtk.ScrolledWindow application_scroll;

    [GtkChild]
    Gtk.SearchEntry search_apps;

    [GtkChild]
    Gtk.Label search_desc;

    AppEntry[] applications;
    private AppEntry selectedApp;

    private Gtk.Application app;

    private Config config;

    public LawnchairWindow (Gtk.Application app) {
        Object (application: app);
        this.app = app;
        setup ();
    }

    private void setup () {
        this.show.connect (() => {
            this.set_keep_above (true);
        });

        config = get_config ();
        Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = config.dark_theme;

        setup_applications ();
        setup_search ();
    }

    private void setup_applications () {
        int prev_y = 0;

        application_grid.set_focus_child.connect ((child) => {
            auto_scroll (child, ref prev_y);
        });

        application_grid.key_press_event.connect ((e) => {
            if (e.keyval == Gdk.Key.Escape) {
                search_apps.grab_focus ();
                return true;
            }

            if (e.keyval == Gdk.Key.Up) {
                if (top_row (selectedApp.app_button)) {
                    search_apps.grab_focus ();
                    return true;
                }
            }

            return false;
        });

        string[] dirs = Environment.get_system_data_dirs ();
        dirs += Environment.get_user_data_dir ();
        applications = get_application_buttons (dirs);
        filter_grid (null);
    }

    private void setup_search () {
        search_apps.grab_focus ();

        search_apps.key_press_event.connect (handle_esc_return);
        search_apps.search_changed.connect (() => {
            search_desc.set_text ("");
            Instance.extension = null;

            var str = search_apps.text.split (",", 2);
            var text = str[0].strip ();

            if (str.length > 1) {
                str = str[1].split (" ");
                var keyword = str[0].strip ().down ();

                if (config.commands.has_key (keyword)) {
                    var command = config.commands[keyword];
                    search_desc.set_text (command.description);

                    var extension = Extension ();
                    extension.command = command.command;

                    var args = new string[] {};
                    for (int i =1; i < str.length; i++) {
                        args += str[i].strip ();
                    }

                    extension.args = args;
                    Instance.extension = extension;
                }
            }

            filter_grid (text);
        });
    }

    private void auto_scroll (Gtk.Widget ? child, ref int prev_y) {
        if (child is Button) {
            Button button = (Button) child;
            selectedApp = button.app;

            int x, y;
            button.translate_coordinates (application_grid, 0, 0, out x, out y);
            Gtk.Allocation scroll_a, button_a;
            application_scroll.get_allocation (out scroll_a);
            button.get_allocation (out button_a);

            if (y == prev_y) {
                // no need to scroll;
                return;
            }

            bool direction_up = false;

            if (y < prev_y) {
                direction_up = true;
            }

            prev_y = y;

            if (y > scroll_a.height) {
                int new_y = y - (scroll_a.height - button_a.height);
                if (direction_up) {
                    new_y = y;
                }
                application_scroll.vadjustment.value = new_y;
            } else if (y < scroll_a.height) {
                application_scroll.vadjustment.value = 0;
            }
        }
    }

    private bool handle_esc_return (Gdk.EventKey e) {
        switch (e.keyval) {
        case Gdk.Key.Escape:
            app.quit ();
            return true;
        case Gdk.Key.Return:
            if (selectedApp != null) {
                selectedApp.app_button.clicked ();
            }

            return true;
        case Gdk.Key.Down:
            var first = first_entry ();
            if (first != null) {
                first.grab_focus ();
                return true;
            }
            break;
        }

        return false;
    }

    Button ? first_entry () {
        var children = application_grid.get_children ();
        if (children.length () > 0) {
            var first = children.nth_data (children.length () - 1);
            if (first is Button) {
                return (Button) first;
            }
        }

        return null;
    }

    bool top_row (Button button) {
        var children = application_grid.get_children ();
        for (int i = 0; i < config.cols; i++) {
            var b = children.nth_data (children.length () - i - 1);
            if (!(b is Button)) {
                return false;
            }

            if (button == (Button) b) {
                return true;
            }
        }

        return false;
    }

    void filter_grid (string ? f) {
        string ? filter = f == null ? null : f.down ();
        application_grid.forall ((element) => application_grid.remove (element));
        GenericArray < AppEntry > matches = new GenericArray < AppEntry > ();

        int count = 0;
        selectedApp = null;

        // filter
        for (int i = 0; i < applications.length; i++) {
            var app = applications[i];
            if (filter != null) {
                if (!app.app_name.down ().contains (filter)
                    && !app.app_search_name.contains (filter)
                    && !app.app_comment.down ().contains (filter)
                    && !app.app_keywords.down ().contains (filter)) {
                    continue;
                }
            }

            matches.add (app);
        }

        // sort
        // horrible bruteforce code.
        // should be done properly someday.
        if (filter != null) {
            matches.sort_with_data ((a, b) => {
                // prioritize name match over comment match
                string[] str = new string[] {
                    a.app_name.down (),
                    b.app_name.down (),
                    a.app_search_name,
                    b.app_search_name,
                    a.app_comment.down (),
                    b.app_comment.down (),
                    a.app_keywords.down (),
                    b.app_keywords.down (),
                };

                for (int i =0; i < str.length; i +=2) {
                    var s1 = str[i] == filter;
                    var s2 = str[i + 1] == filter;

                    if (s1 != s2) {
                        return s1 ? -1 : 1;
                    }

                    if (s1 && s2) {
                        break;
                    }

                    s1 = str[i].has_prefix (filter);
                    s2 = str[i + 1].has_prefix (filter);

                    if (s1 != s2) {
                        return s1 ? -1 : 1;
                    }

                    if (s1 && s2) {
                        break;
                    }

                    s1 = str[i].contains (filter);
                    s2 = str[i + 1].contains (filter);

                    if (s1 != s2) {
                        return s1 ? -1 : 1;
                    }

                    if (s1 && s2) {
                        break;
                    }
                }

                return strcmp (a.app_name.down (), b.app_name.down ());
            });
        }

        // add to grid
        foreach (AppEntry app in matches.data) {
            application_grid.attach (app.app_button, count % config.cols, count / config.cols);
            count++;

            if (selectedApp == null) {
                selectedApp = app;
            }
        }

        // 12 is a decent list for the view
        for (int i =count; i < 12; i++) {
            Gtk.Label dummy = new Gtk.Label (null);

            if (i == 0) {
                dummy.set_text ("\n\nNot found");
            }

            dummy.can_focus = false;
            dummy.show ();

            // centralise empty placeholders when no result is found
            int size = count == 0 ? 1 : config.cols;
            application_grid.attach (dummy, i % size, i / size);
        }

        // scroll back to top
        application_scroll.vadjustment.value = 0;
    }
}

