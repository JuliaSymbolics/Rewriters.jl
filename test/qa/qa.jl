using SciMLTesting
using Rewriters

run_qa(
    Rewriters;
    ei_kwargs = (;
        all_qualified_accesses_are_public = (; ignore = (Symbol("@nexprs"),)),
    ),
)
