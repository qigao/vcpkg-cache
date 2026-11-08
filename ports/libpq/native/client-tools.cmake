# Use the generated C scanners/parsers shipped in PostgreSQL's release archive.
# These are the same inputs the upstream Make build uses without regeneration.
function(pg_client_tool name directory)
  set(sources ${ARGN})
  list(TRANSFORM sources PREPEND "${src}/${directory}/")
  list(TRANSFORM sources APPEND .c)
  add_executable(${name} ${sources})
  target_include_directories(${name} PRIVATE "${src}/${directory}")
  # Resolve frontend helper symbols before the DLL import library: libpq also
  # exports compatibility functions implemented by pgcommon (e.g. pg_utf_mblen).
  target_link_libraries(${name} PRIVATE pgfeutils pgcommon pgport pq pg_frontend Threads::Threads)
  install(TARGETS ${name} RUNTIME DESTINATION tools/libpq)
endfunction()

set(fe_sources archive cancel conditional connect_utils mbprint option_utils
  parallel_slot print psqlscan query_utils recovery_gen simple_list string_utils)
list(TRANSFORM fe_sources PREPEND "${src}/fe_utils/")
list(TRANSFORM fe_sources APPEND .c)
add_library(pgfeutils STATIC ${fe_sources})
target_link_libraries(pgfeutils PUBLIC pgcommon pgport pg_frontend)
target_compile_definitions(pgfeutils PRIVATE FD_SETSIZE=1024)

pg_client_tool(pg_amcheck bin/pg_amcheck pg_amcheck)
pg_client_tool(pg_verifybackup bin/pg_verifybackup parse_manifest pg_verifybackup)
pg_client_tool(pgbench bin/pgbench pgbench exprscan exprparse)
target_compile_definitions(pgbench PRIVATE FD_SETSIZE=1024)
pg_client_tool(psql bin/psql command common copy crosstabview describe help input
  large_obj mainloop prompt psqlscanslash sql_help startup stringutils tab-complete variables)
install(FILES "${src}/bin/psql/psqlrc.sample" DESTINATION share/libpq)

set(dump_sources compress_gzip compress_io compress_lz4 compress_none
  compress_zstd dumputils parallel pg_backup_archiver pg_backup_custom
  pg_backup_db pg_backup_directory pg_backup_null pg_backup_tar pg_backup_utils)
list(TRANSFORM dump_sources PREPEND "${src}/bin/pg_dump/")
list(TRANSFORM dump_sources APPEND .c)
add_library(pgdump_common STATIC ${dump_sources})
target_link_libraries(pgdump_common PUBLIC pq pgfeutils pgcommon pgport pg_frontend)
pg_client_tool(pg_dump bin/pg_dump common pg_dump pg_dump_sort)
pg_client_tool(pg_dumpall bin/pg_dump pg_dumpall)
pg_client_tool(pg_restore bin/pg_dump pg_restore)
foreach(tool IN ITEMS pg_dump pg_dumpall pg_restore)
  target_link_libraries(${tool} PRIVATE pgdump_common)
endforeach()

set(backup_sources bbstreamer_file bbstreamer_gzip bbstreamer_inject
  bbstreamer_lz4 bbstreamer_tar bbstreamer_zstd receivelog streamutil walmethods)
list(TRANSFORM backup_sources PREPEND "${src}/bin/pg_basebackup/")
list(TRANSFORM backup_sources APPEND .c)
add_library(pgbackup_common STATIC ${backup_sources})
target_link_libraries(pgbackup_common PUBLIC pq pgfeutils pgcommon pgport pg_frontend)
foreach(tool IN ITEMS pg_basebackup pg_receivewal pg_recvlogical)
  pg_client_tool(${tool} bin/pg_basebackup ${tool})
  target_link_libraries(${tool} PRIVATE pgbackup_common)
endforeach()
foreach(tool IN ITEMS createdb dropdb createuser dropuser clusterdb vacuumdb reindexdb pg_isready)
  pg_client_tool(${tool} bin/scripts ${tool} common)
endforeach()
pg_client_tool(ecpg_preproc interfaces/ecpg/preproc ../ecpglib/typename c_keywords
  descriptor ecpg ecpg_keywords keywords output parser pgc preproc type variable)
target_include_directories(ecpg_preproc PRIVATE "${src}/interfaces/ecpg/include")
set_target_properties(ecpg_preproc PROPERTIES OUTPUT_NAME ecpg)
if(PG_NLS)
  foreach(directory IN ITEMS pg_amcheck pg_verifybackup pgbench psql pg_dump pg_basebackup)
    pg_install_catalogs(bin/${directory} ${directory}-16)
  endforeach()
  pg_install_catalogs(bin/scripts pgscripts-16)
  pg_install_catalogs(interfaces/ecpg/preproc ecpg-16)
endif()
