=============
Special Files
=============

As part of the execution of the toolbox commands, some special files
will be generated in the `$ARTIFACT_DIR` directory. They will be
recognized by the code in `ci-dashboard
<https://github.com/openshift-psap/ci-dashboard/>`_ repository and
interpreted to enhance the dashboard display:

- ``$ARTIFACT_DIR/<toolbox directory>/_ansible.log.json``: `JSON
  <https://docs.ansible.com/ansible/latest/collections/ansible/posix/json_callback.html>`_
  array of the ansible tasks executed as part of the toolbox
  command. In particular, in this file, we parse the ``stats``
  information of the last entry:

.. code-block:: json

    {
      "log_level": "info",
      "scope": "playbook",
      "stats": {
          "localhost": {
              "changed": 4,
              "failures": 0,
              "ignored": 0,
              "ok": 5,
              "rescued": 0,
              "skipped": 2,
              "unreachable": 0
          }
      },
      "status": "finished"
    }


- ``$ARTIFACT_DIR/FAILURE``: the presence this file after the CI
  execution indicates that the testing failed.

- ``$ARTIFACT_DIR/FLAKE``: the presence of this file after a toolbox
  command fail indicates that a known flake occurred. The file
  contains a brief description of the problem that happened.

- ``$ARTIFACT_DIR/UNREACHABLE``: the presence this file after the CI
  execution indicates that the testing failed and the cluster was
  unreachable during our tear-down execution.
