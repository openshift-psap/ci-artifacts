=============
Operand Build
=============

.. _toolbox_operand_build:

Build All
=========

* Creates BuildConfig resources for each of the gpu-operator operands and waits
  for all of them to finish the build.

.. code-block:: shell

    ./toolbox/cluster/build_all.sh

Clean All
=========

* Deletes all BuildConfig, Build and ImageStream resources created during the building
  of the operands.

.. code-block:: shell

    ./toolbox/cluster/clean_all.sh

