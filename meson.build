project('asdf', 'd', version : '2.0.0', license: 'BSL-1.0')

asdf_dir = include_directories('source/')

asdf_src = [
    'source/asdf/asdf.d',
    'source/asdf/jsonbuffer.d',
    'source/asdf/jsonparser.d',
    'source/asdf/outputarray.d',
    'source/asdf/package.d',
    'source/asdf/serialization.d',
    'source/asdf/transform.d',
    'source/asdf/utility.d',
]

asdf_lib = library(meson.project_name(),
    asdf_src,
    include_directories: asdf_dir,
    install: true,
    version: meson.project_version(),
)

asdf_dep = declare_dependency(
    link_with: [asdf_lib],
    include_directories: asdf_dir,
)

install_subdir('source/',
    strip_directory : true,
    install_dir: 'include/d/' + meson.project_name(),
)

import('pkgconfig').generate(
    name: meson.project_name(),
    description: 'JSON serialisation library for Dlang.',
    subdirs: 'd/' + meson.project_name(),
    libraries: [asdf_lib],
    version: meson.project_version(),
)

if get_option('with_test')

    asdf_test_exe = executable(meson.project_name() + '-test',
        asdf_src,
        include_directories: asdf_dir,
        d_unittest: true,
        d_module_versions: ['mir_test'],
        link_args: '-main',
    )

    test(meson.project_name() + '-test', asdf_test_exe)

endif
