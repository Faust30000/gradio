/* This file is part of Gradio.
 *
 * Gradio is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Gradio is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Gradio.  If not, see <http://www.gnu.org/licenses/>.
 */

using Sqlite;

namespace Gradio{

	public class Library : Gtk.Box{
		public signal void added_radio_station(RadioStation s);
		public signal void removed_radio_station(RadioStation s);

		private StationProvider station_provider;
		public static StationModel station_model;
		public static CollectionModel collection_model;

		private Sqlite.Database db;
		private string db_error_message;

		string database_path;
		string data_path;
		string dir_path;

		public Library(){
			database_path = Path.build_filename (Environment.get_user_data_dir (), "gradio", "gradio.db");
			data_path = Path.build_filename (Environment.get_user_data_dir (), "gradio", "library.gradio");
			dir_path = Path.build_filename (Environment.get_user_data_dir (), "gradio");

			station_model = new StationModel();
			station_provider = new StationProvider(ref station_model);
			collection_model = new CollectionModel();

			open_database();
		}

		public bool add_station_to_collection(string collection_id, RadioStation station){
			// station must be in the library
			if((!station_model.contains_station(station)) || station == null)
				return false;

			Collection coll = (Collection)collection_model.get_collection_by_id(collection_id);

			// 1. Remove the station from the previous collection
			Statement stmt; int rc = 0; int cols;
			if ((rc = db.prepare_v2 ("SELECT collection_id from library WHERE station_id = '"+station.id+"';", -1, out stmt, null)) == 1) {
				critical ("SQL error: %d, %s\n", rc, db.errmsg ());
				return false;
			}
			cols = stmt.column_count();
			do {
				rc = stmt.step();
				switch (rc) {
				case Sqlite.DONE:
					break;
				case Sqlite.ROW:
					Collection previous_coll = collection_model.get_collection_by_id(stmt.column_text(0));
					previous_coll.remove_station(station);
					break;
				default:
					printerr ("Error: %d, %s\n", rc, db.errmsg ());
					break;
				}
			} while (rc == Sqlite.ROW);


			// 2. Add the station to the new collection (if the collection exists)
			if(coll != null){
				coll.add_station(station);

				string query = "UPDATE library SET collection_id = '"+collection_id+"' WHERE station_id = "+station.id+";";

				int return_code = db.exec (query, null, out db_error_message);
				if (return_code != Sqlite.OK) {
					critical ("Could not add item to collection: %s\n", db_error_message);
					return false;
				}else{
					message("Successfully added station to collection %s", collection_id);
					return true;
				}
			}else{
				warning("Adding station to collection %s: Collection not found.", collection_id);
				return false;
			}
			return false;
		}

		public bool add_new_collection(Collection collection){
			if(collection_model.contains_collection(collection) || collection == null)
				return true;

			string query = "INSERT INTO collections (collection_id,collection_name) VALUES ('"+collection.id+"', '"+collection.name+"');";

			int return_code = db.exec (query, null, out db_error_message);
			if (return_code != Sqlite.OK) {
				critical ("Could not add collection to database: %s\n", db_error_message);
				return false;
			}else{
				collection_model.add_collection(collection);
				return true;
			}
		}

		public bool remove_collection(Collection collection){
			message("Removing collection %s from the library.", collection.name);
			if(!collection_model.contains_collection(collection) || collection == null)
				return true;


			// 1. Delete the collection itself
			string query = "DELETE FROM collections WHERE collection_id=" + collection.id;

			int return_code = db.exec (query, null, out db_error_message);
			if (return_code != Sqlite.OK) {
				critical ("Could not remove collection from database: %s\n", db_error_message);
				return false;
			}else{
				Idle.add(() => {
					collection_model.remove_collection(collection);
					return false;
				});
			}

			// 2. Remove the collection_id from the stations
			query = "UPDATE library SET collection_id = '0' WHERE collection_id = "+collection.id+";";

			return_code = db.exec (query, null, out db_error_message);
			if (return_code != Sqlite.OK) {
				critical ("Could not update collection id: %s\n", db_error_message);
				return false;
			}else{
				return true;
			}

		}

		public bool add_radio_station(RadioStation station){
			if(station_model.contains_station(station) || station == null)
				return true;

			string query = "INSERT INTO library (station_id,collection_id) VALUES ("+station.id+", '0');";

			int return_code = db.exec (query, null, out db_error_message);
			if (return_code != Sqlite.OK) {
				critical ("Could not add item to database: %s\n", db_error_message);
				return false;
			}else{
				station_model.add_station(station);
				return true;
			}
		}

		public bool remove_radio_station(RadioStation station){
			message("Removing station %s from the library.", station.title);
			if(!station_model.contains_station(station) || station == null)
				return true;

			// 1. Remove the station from the collection
			Statement stmt; int rc = 0; int cols;
			if ((rc = db.prepare_v2 ("SELECT collection_id from library WHERE station_id = '"+station.id+"';", -1, out stmt, null)) == 1) {
				critical ("SQL error: %d, %s\n", rc, db.errmsg ());
				return false;
			}
			cols = stmt.column_count();
			do {
				rc = stmt.step();
				switch (rc) {
				case Sqlite.DONE:
					break;
				case Sqlite.ROW:
					Collection previous_coll = collection_model.get_collection_by_id(stmt.column_text(0));
					previous_coll.remove_station(station);
					break;
				default:
					printerr ("Error: %d, %s\n", rc, db.errmsg ());
					break;
				}
			} while (rc == Sqlite.ROW);


			// 2. Remove the station itself
			string query = "DELETE FROM library WHERE station_id=" + station.id;

			int return_code = db.exec (query, null, out db_error_message);
			if (return_code != Sqlite.OK) {
				critical ("Could not remove station from database: %s\n", db_error_message);
				return false;
			}else{
				Idle.add(() => {
					station_model.remove_station(station);
					removed_radio_station(station);
					return false;
				});

				return true;
			}
		}


		private void open_database(){
			message("Open database...");

			File file = File.new_for_path (database_path);

			if(!file.query_exists()){
				message("No database found.");
				create_database();
				return;
			}

			int return_code = Sqlite.Database.open (database_path.to_string(), out db);

			if (return_code!= Sqlite.OK) {
				critical ("Can't open database: %d: %s\n", db.errcode (), db.errmsg ());
				return;
			}

			read_database();

			message("Successfully opened database!");
		}

		private void read_database(){
			message("Reading database data...");
			read_collections();
			read_stations();
		}

		private void read_stations(){
			Statement stmt;
			int rc = 0;
			int cols;

			if ((rc = db.prepare_v2 ("SELECT * FROM library;", -1, out stmt, null)) == 1) {
				critical ("SQL error: %d, %s\n", rc, db.errmsg ());
				return;
			}

			cols = stmt.column_count();
			do {
				rc = stmt.step();
				switch (rc) {
				case Sqlite.DONE:
					break;
				case Sqlite.ROW:
					message("Found station: " + stmt.column_text(0));
					station_provider.add_station_by_id(int.parse(stmt.column_text(0)));

					if(stmt.column_text(1) != "0"){
						Collection coll = collection_model.get_collection_by_id(stmt.column_text(1));
						coll.add_station_by_id(int.parse(stmt.column_text(0)));
					}

					break;
				default:
					printerr ("Error: %d, %s\n", rc, db.errmsg ());
					break;
				}
			} while (rc == Sqlite.ROW);
		}

		private void read_collections(){
			Statement stmt;
			int rc = 0;
			int cols;

			if ((rc = db.prepare_v2 ("SELECT * FROM collections;", -1, out stmt, null)) == 1) {
				critical ("SQL error: %d, %s\n", rc, db.errmsg ());
				return;
			}

			cols = stmt.column_count();
			do {
				rc = stmt.step();
				switch (rc) {
				case Sqlite.DONE:
					break;
				case Sqlite.ROW:
					message("Found collection: " + stmt.column_text(1));

					Collection coll = new Collection(stmt.column_text(1), stmt.column_text(0));
					collection_model.add_collection(coll);
					break;
				default:
					printerr ("Error: %d, %s\n", rc, db.errmsg ());
					break;
				}
			} while (rc == Sqlite.ROW);
		}

		private void create_database(){
			message("Create new database...");

			File file = File.new_for_path (database_path);

			try{
				if(!file.query_exists()){
					// create dir
					File dir = File.new_for_path (Path.build_filename (Environment.get_user_data_dir (), "gradio"));
					dir.make_directory_with_parents();

					// create file
					file.create (FileCreateFlags.NONE);

					open_database();
					init_database();
				}else{
					warning("Database already exists.");
					open_database();
				}
			}catch(Error e){
				critical("Cannot create new database: " + e.message);
			}
		}

		private void init_database(){
			message("Initialize database...");

			string query = """
				CREATE TABLE "library" ('station_id' INTEGER, 'collection_id' INTEGER);
				CREATE TABLE "collections" ('collection_id' INTEGER, 'collection_name' TEXT)
				""";

			int return_code = db.exec (query, null, out db_error_message);
			if (return_code != Sqlite.OK) {
				critical ("Could not initialize database: %s\n", db_error_message);
				return ;
			}

			message("Successfully initialized database!");
			open_database();
		}

	}
}
