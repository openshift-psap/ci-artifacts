from collections import defaultdict
import datetime
import statistics as stats

from dash import html
import plotly.graph_objs as go
import pandas as pd
import plotly.express as px

import matrix_benchmarking.plotting.table_stats as table_stats
import matrix_benchmarking.common as common

def register():
    SpawnTime("User Execution Time")
    RunTimeDistribution("Median runtime timeline")

def add_progress(entry, hide_failed_users, only_prefix=[], remove_prefix=True):
    data = []
    for user_idx, user_data in entry.results.user_data.items():
        if not user_data: continue

        failures = user_data.exit_code
        if failures and hide_failed_users: continue

        previous_step_time = entry.results.tester_job.creation_time

        if not user_data.progress: continue

        for step_idx, (step_name, step_time) in enumerate(user_data.progress.items()):
            timelength = (step_time - previous_step_time).total_seconds()
            previous_step_time = step_time

            if only_prefix:
                keep = False
                for prefix in only_prefix:
                    if step_name.startswith(prefix):
                        keep = True
                if not keep: continue


            entry_data = {}

            entry_data["Step Name"] = step_name if not remove_prefix else step_name.partition(".")[-1]
            entry_data["Step Duration"] = timelength
            entry_data["Step Index"] = step_idx

            entry_data["User Index"] = user_idx
            entry_data["User Name"] = f"User #{user_idx}"
            if failures:
                entry_data["User Name"] = f"<b>{entry_data['User Name']}</b>"

            data.insert(0, entry_data)

    return data


class SpawnTime():
    def __init__(self, name):
        self.name = name
        self.id_name = name

        table_stats.TableStats._register_stat(self)
        common.Matrix.settings["stats"].add(self.name)

    def do_hover(self, meta_value, variables, figure, data, click_info):
        return "nothing"

    def do_plot(self, ordered_vars, settings, setting_lists, variables, cfg):

        expe_cnt = common.Matrix.count_records(settings, setting_lists)
        if expe_cnt != 1:
            return {}, f"ERROR: only one experiment must be selected. Found {expe_cnt}."

        for entry in common.Matrix.all_records(settings, setting_lists):
            pass # entry is set

        data = []

        hide_launch_delay = cfg.get("hide_launch_delay", False)
        keep_failed_steps = cfg.get("keep_failed_steps", False)
        hide_failed_users = cfg.get("hide_failed_users", False)
        hide = cfg.get("hide", None)

        data += add_progress(entry, hide_failed_users)

        if not data:
            return None, "No data available"

        df = pd.DataFrame(data).sort_values(by=["User Index", "Step Index"], ascending=True)

        fig = px.area(df, y="User Name", x="Step Duration", color="Step Name")
        fig.update_layout(xaxis_title="Timeline (in seconds)")
        fig.update_layout(yaxis_title="")
        fig.update_yaxes(autorange="reversed") # otherwise users are listed from the bottom up

        if hide_launch_delay:
            fig.for_each_trace(lambda trace: trace.update(visible="legendonly")
                               if not trace.name[0].isdigit() else ())

        title = "Execution Time of the User Steps"
        if keep_failed_steps:
            title += " with the failed steps"
        if hide_failed_users:
            title += " without the failed users"
        if hide_launch_delay:
            title += " without the launch delay"
        fig.update_layout(title=title, title_x=0.5,)

        return fig, ""

class RunTimeDistribution():
    def __init__(self, name, show_successes=False):
        self.name = name
        self.id_name = name

        table_stats.TableStats._register_stat(self)
        common.Matrix.settings["stats"].add(self.name)

    def do_hover(self, meta_value, variables, figure, data, click_info):
        return "nothing"

    def do_plot(self, ordered_vars, settings, setting_lists, variables, cfg):
        user_counts = set()

        if not common.Matrix.has_records(settings, setting_lists):
            return None, "No experiments to plot"

        data = []
        for entry in common.Matrix.all_records(settings, setting_lists):
            results = entry.results
            entry_name = ", ".join([f"{key}={entry.settings.__dict__[key]}" for key in variables])

            user_counts.add(results.user_count)

            previous_step_time = entry.results.tester_job.creation_time
            for user_index, user_data in entry.results.user_data.items():
                if user_data.exit_code != 0:
                    continue

                for step_name, step_time in user_data.progress.items():

                    data.append(dict(
                        UserCount=results.user_count,
                        Step=step_name + entry_name,
                        Time=(step_time - previous_step_time).total_seconds(),
                    ))
                    previous_step_time = step_time

        data = add_progress(entry, hide_failed_users=True, only_prefix=["ansible"], remove_prefix=True)

        if not data:
            return None, "No data to plot ..."

        data_df = pd.DataFrame(data)
        data_df = data_df.sort_values(by=["Step Name"])

        stats_data = []
        base_value = 0
        steps = data_df["Step Name"].unique()
        notebook_ready_time = None
        msg = []
        for step_name in steps:
            step_df = data_df[data_df["Step Name"] == step_name]
            q1, median, q3 = stats.quantiles(step_df["Step Duration"])
            q1_dist = median-q1
            q3_dist = q3-median
            stats_data.append(dict(
                Steps=step_name,
                MedianDuration=median,
                Q1=q1_dist,
                Q3=q3_dist,
                UserCount=str(entry.results.user_count),
                Base=base_value,
            ))

            q1_txt = f"-{q1_dist:.0f}s" if round(q1_dist) >= 2 else ""
            q3_txt = f"+{q3_dist:.0f}s" if round(q3_dist) >= 2 else ""
            msg += [f"{step_name}: {median:.0f}s {q1_txt}{q3_txt}", html.Br()]

            base_value += median
            if step_name.endswith("Go to JupyterLab Page"):
                notebook_ready_time = base_value
                msg += ["---", html.Br()]

        stats_df = pd.DataFrame(stats_data)

        fig = px.bar(stats_df,
                     x="MedianDuration", y="Steps", color="Steps", base="Base",
                     error_x_minus="Q1", error_x="Q3",
                     title="Median runtime timeline")

        if notebook_ready_time:
            fig.add_scatter(name="Time to reach JupyterLab",
                            x=[notebook_ready_time, notebook_ready_time],
                            y=[steps[0], steps[-1]])
        fig.update_layout(xaxis_title="Timeline (in seconds). Error bars show Q1 and Q3.")
        fig.update_layout(yaxis_title="", title_x=0.5,)

        return fig, msg
